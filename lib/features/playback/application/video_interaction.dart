import 'dart:math' show max;

import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/application/coin_balance.dart';

typedef VideoInteractionTarget = ({String bvid, int? episode});
typedef VideoReactions = ({bool liked, bool disliked, num coins, bool favored});

class VideoInteraction {
  VideoInteraction({
    required this.target,
    required this.read,
    required this.publish,
  });

  final VideoInteractionTarget? Function() target;
  final VideoReactions Function() read;
  final void Function(VideoReactions state, {required bool fromQuery}) publish;
  bool _busy = false;
  int _revision = 0;
  bool get busy => _busy;

  bool Function() captureOwner() {
    final video = target();
    final account = Accounts.main;
    return () =>
        video != null && video == target() && identical(account, Accounts.main);
  }

  Future<Error?> refresh({required bool pgc}) async {
    final video = target();
    if (_busy || video == null) return null;
    if (pgc && video.episode == null) return null;
    final account = Accounts.main;
    final current = captureOwner();
    final revision = ++_revision;
    final LoadingState<VideoReactions> result;
    if (pgc) {
      final response = await VideoHttp.pgcLikeCoinFav(
        epId: video.episode!,
        account: account,
      );
      result = switch (response) {
        Success(:final response) => Success((
          liked: response.like == 1,
          disliked: false,
          coins: response.coinNumber,
          favored: response.favorite == 1,
        )),
        Error() => response,
        Loading() => LoadingState.loading(),
      };
    } else {
      final response = await VideoHttp.videoRelation(
        bvid: video.bvid,
        account: account,
      );
      result = switch (response) {
        Success(:final response) => Success((
          liked: response.like,
          disliked: response.dislike,
          coins: response.coin,
          favored: response.favorite,
        )),
        Error() => response,
        Loading() => LoadingState.loading(),
      };
    }
    if (!current() || revision != _revision) return null;
    if (result case Success(:final response)) {
      publish(response, fromQuery: true);
    }
    return result is Error ? result : null;
  }

  Future<LoadingState<String?>?> toggleLike() =>
      _write((video, account, current) async {
        final liked = !read().liked;
        final result = await VideoHttp.likeVideo(
          bvid: video.bvid,
          type: liked,
          account: account,
        );
        if (result case Success(:final response) when current()) {
          final before = read();
          publish((
            liked: liked,
            disliked: !liked && before.disliked,
            coins: before.coins,
            favored: before.favored,
          ), fromQuery: false);
          return Success(liked ? response ?? '点赞成功' : '取消赞');
        }
        return result;
      });

  Future<LoadingState<String?>?> toggleDislike() =>
      _write((video, account, current) async {
        final disliked = !read().disliked;
        final result = await VideoHttp.dislikeVideo(
          bvid: video.bvid,
          type: disliked,
          account: account,
        );
        if (!result.isSuccess) return result as Error;
        if (current()) {
          final before = read();
          publish((
            liked: !disliked && before.liked,
            disliked: disliked,
            coins: before.coins,
            favored: before.favored,
          ), fromQuery: false);
        }
        return Success(disliked ? '点踩成功' : '取消踩');
      });

  Future<LoadingState<String?>?> coin(
    int amount, {
    required bool withLike,
    required int limit,
  }) => _write((video, account, current) async {
    if (amount > 0 && read().coins + amount > limit) {
      return const Error('达到投币上限啦~');
    }
    final result = await VideoHttp.coinVideo(
      bvid: video.bvid,
      multiply: amount,
      selectLike: withLike ? 1 : 0,
      account: account,
    );
    if (!result.isSuccess) return result as Error;
    _charge(account, amount);
    if (current()) {
      final before = read();
      publish((
        liked: withLike || before.liked,
        disliked: before.disliked,
        coins: before.coins + amount,
        favored: before.favored,
      ), fromQuery: false);
    }
    return const Success('投币成功');
  });

  Future<LoadingState<String?>?> triple({
    required bool pgc,
    int? seasonId,
    required void Function() onAccepted,
  }) => _write((video, account, current) async {
    onAccepted();
    final before = read();
    if (before.liked && before.coins != 0 && before.favored) {
      return const Success('已三连');
    }
    final episode = video.episode;
    if (pgc && episode == null) return const Error('剧集信息不完整，请刷新后重试');
    final result = await FavoriteLibrary.legacy
        .write<({bool liked, num? totalCoins, int spent, bool favored})>(
          account,
          () async {
            if (!current()) return const Error('视频或账号已更新');
            if (pgc) {
              final response = await VideoHttp.pgcTriple(
                epId: episode!,
                seasonId: seasonId,
                account: account,
              );
              if (response case Success(:final response)) {
                final total = response.coin == 1 ? response.coinNumber : null;
                return Success((
                  liked: response.like == 1,
                  totalCoins: total,
                  spent: total == null
                      ? 0
                      : max(0, total - before.coins).toInt(),
                  favored: response.favorite == 1,
                ));
              }
              return response as Error;
            }
            final response = await VideoHttp.ugcTriple(
              bvid: video.bvid,
              account: account,
            );
            if (response case Success(:final response)) {
              final spent = response.coin ? response.multiply : 0;
              return Success((
                liked: response.like,
                totalCoins: null,
                spent: spent,
                favored: response.fav,
              ));
            }
            return response as Error;
          },
        );
    if (!result.isSuccess) return result as Error;
    final receipt = result.data;
    _charge(account, receipt.spent);
    if (!current()) return null;
    final latest = read();
    final after = (
      liked: latest.liked || receipt.liked,
      disliked: latest.disliked && !(receipt.liked && !latest.liked),
      coins: receipt.totalCoins ?? latest.coins + receipt.spent,
      favored: latest.favored || receipt.favored,
    );
    publish(after, fromQuery: false);
    return Success(
      after.liked && after.coins != 0 && after.favored
          ? '三连成功'
          : '三连未全部完成，请核对点赞、投币和收藏状态',
    );
  });

  Future<LoadingState<String?>?> _write(
    Future<LoadingState<String?>?> Function(
      VideoInteractionTarget,
      Account,
      bool Function(),
    )
    action,
  ) async {
    final video = target();
    if (_busy || video == null) return null;
    final account = Accounts.main;
    if (!account.isLogin) return const Error('账号未登录');
    final current = captureOwner();
    _busy = true;
    _revision++;
    try {
      final result = await action(video, account, current);
      return current() ? result : null;
    } catch (error, stackTrace) {
      logger.w('视频互动未完成', error: error.runtimeType, stackTrace: stackTrace);
      return current() ? const UnknownResult() : null;
    } finally {
      _busy = false;
      _revision++;
    }
  }

  void _charge(Account account, int amount) {
    CoinBalance.instance.recordSpend(account, amount);
  }
}
