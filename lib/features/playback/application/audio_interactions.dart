import 'package:flutter/foundation.dart' show listEquals;
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/playback/data/audio_interaction_repository.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/global_data.dart';

class AudioInteractions {
  AudioInteractions({
    required this._target,
    required this._selectionRevision,
    required this._read,
    required this._publish,
  });

  final AudioTarget? Function() _target;
  final int Function() _selectionRevision;
  final AudioTrack? Function() _read;
  final void Function(AudioTrack) _publish;
  bool Function()? _pendingWrite;
  Account? _account;
  int _statsRevision = 0;

  int get statsRevision => _statsRevision;

  static bool _sameTrack(AudioTarget? first, AudioTarget second) =>
      first != null && first.oid == second.oid && first.type == second.type;

  void accept(AudioTrack track, {required int requestedAt}) {
    final account = Accounts.main;
    final previous = _read();
    final preserve =
        ((_pendingWrite?.call() ?? false) || requestedAt != _statsRevision) &&
        previous != null &&
        identical(account, _account) &&
        _sameTrack(previous.info.target, track.info.target);
    _account = account;
    _publish(preserve ? track.withStats(previous.stats) : track);
  }

  Error? unavailable() {
    final target = _target();
    if (target == null ||
        !_sameTrack(_read()?.info.target, target) ||
        (_account != null && !identical(_account, Accounts.main))) {
      return const Error('曲目信息待更新，请刷新播放列表后重试');
    }
    return null;
  }

  bool Function() captureSelection() {
    final track = _read()?.info;
    final account = Accounts.main;
    final target = _captureTarget();
    final revision = _selectionRevision();
    return () =>
        target != null &&
        revision == _selectionRevision() &&
        identical(track, _read()?.info) &&
        _owns(account, target);
  }

  AudioTarget? _captureTarget() {
    final current = _target();
    if (current == null) return null;
    return (
      oid: current.oid,
      type: current.type,
      parts: List.unmodifiable(current.parts),
    );
  }

  bool _owns(Account account, AudioTarget target) {
    final current = _target();
    return _sameTrack(current, target) &&
        listEquals(current!.parts, target.parts) &&
        _sameTrack(_read()?.info.target, target) &&
        identical(account, Accounts.main) &&
        (_account == null || identical(account, _account));
  }

  Future<LoadingState<String>?> toggleLike() =>
      _write((account, target, current) async {
        final liked = !_read()!.stats.liked;
        final result = await AudioInteractionRepository.like(
          account,
          target,
          liked,
        );
        if (result.isSuccess && current()) _confirm(like: liked);
        return result;
      });

  Future<LoadingState<String>?> triple() =>
      _write((account, target, current) async {
        final previousCoins = _read()!.stats.viewerCoins;
        final result = await FavoriteLibrary.legacy.write(
          account,
          () => AudioInteractionRepository.triple(account, target),
        );
        if (result case Success(:final response)) {
          final addedCoins = response.coined && previousCoins == 0 ? 2 : 0;
          _charge(account, addedCoins);
          if (current()) {
            _confirm(
              like: response.liked ? true : null,
              addedCoins: _read()!.stats.viewerCoins == 0 ? addedCoins : 0,
              favorite: response.favored ? true : null,
            );
          }
          return Success(
            response.liked && response.coined && response.favored
                ? '三连成功'
                : '部分操作未完成，请核对点赞、投币和收藏状态',
          );
        }
        return result is Error ? result : null;
      });

  Future<LoadingState<String>?> coin(int amount, bool withLike) => _write((
    account,
    target,
    current,
  ) async {
    final track = _read()!;
    final before = track.stats.viewerCoins;
    if (amount <= 0 || before + amount > (track.info.copyright == 2 ? 1 : 2)) {
      return const Error('达到投币上限啦~');
    }
    final result = await AudioInteractionRepository.coin(
      account,
      target,
      amount,
      withLike,
    );
    if (!result.isSuccess) return result is Error ? result : null;
    _charge(account, amount);
    if (current()) {
      _confirm(
        like: withLike ? true : null,
        addedCoins: _read()!.stats.viewerCoins == before ? amount : 0,
      );
    }
    return const Success('投币成功');
  });

  Future<LoadingState<String>?> quickFavorite() =>
      _write((account, target, current) async {
        final result = await FavoriteLibrary.legacy.quick(
          account,
          (target.oid, target.type == 1 ? 2 : 12),
          isCurrent: current,
        );
        if (result case Success(:final response)) {
          if (current()) confirmFavorite(response);
          return Success(response ? '收藏成功' : '取消收藏成功');
        }
        return result is Error ? result : null;
      });

  void confirmFavorite(bool favored) => _confirm(favorite: favored);

  void _confirm({bool? like, int addedCoins = 0, bool? favorite}) {
    final previous = _read();
    if (previous == null) return;
    _statsRevision++;
    _publish(
      previous.withStats(
        previous.stats.confirm(
          like: like,
          addedCoins: addedCoins,
          favorite: favorite,
        ),
      ),
    );
  }

  Future<LoadingState<String>?> _write(
    Future<LoadingState<String>?> Function(
      Account,
      AudioTarget,
      bool Function(),
    )
    send,
  ) async {
    final target = _captureTarget();
    if (target == null || _pendingWrite != null) return null;
    final account = Accounts.main;
    if (!account.isLogin) return const Error('账号未登录');
    if (unavailable() case final error?) return error;
    final revision = _selectionRevision();
    bool current() =>
        revision == _selectionRevision() && _owns(account, target);
    _pendingWrite = current;
    try {
      final result = await send(account, target, current);
      return current() ? result : null;
    } catch (error, stackTrace) {
      logger
          .scoped('audio')
          .w('音频互动未完成', error: error.runtimeType, stackTrace: stackTrace);
      return current() ? const UnknownResult() : null;
    } finally {
      _pendingWrite = null;
    }
  }

  static void _charge(Account account, int amount) {
    if (amount > 0 && identical(account, Accounts.main)) {
      GlobalData().afterCoin(amount);
    }
  }
}
