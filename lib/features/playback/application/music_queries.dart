import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/music.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_detail.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_recommend_list.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/dimension.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef MusicRecommendArgs = ({String id, MusicDetail item});
typedef MusicVideoTarget = ({String bvid, int cid, Dimension? dimension});

final musicRecommendationsProvider = FutureProvider.autoDispose
    .family<List<BgmRecommend>?, String>((ref, id) async {
      final account = ref.watch(recommendAccountProvider);
      final result = await MusicHttp.bgmRecommend(id, account: account);
      final data = result.data;
      return data == null ? null : List.unmodifiable(data);
    }, retry: (_, _) => null);

abstract final class MusicQueries {
  static Future<LoadingState<MusicDetail>> detail(Account account, String id) =>
      MusicHttp.bgmDetail(id, account: account);

  static Future<LoadingState<void>> setWish(
    Account account,
    String id,
    bool remove,
  ) => MusicHttp.wishUpdate(id, remove, account: account);

  static Future<LoadingState<MusicVideoTarget>> openVideo(
    BgmRecommend item,
    bool Function() isCurrent,
  ) async {
    final account = Accounts.heartbeat;
    final bvid = item.bvid;
    if (bvid == null || bvid.trim().isEmpty) {
      return const Error('视频标识缺失，请刷新列表');
    }
    int? cid = item.cid;
    Dimension? dimension;
    if (cid == null || cid <= 0) {
      final result = await SearchHttp.pageWithDimension(
        bvid: bvid,
        account: account,
      );
      if (!identical(account, Accounts.heartbeat) || !isCurrent()) {
        return LoadingState.loading();
      }
      if (result case Error error) return error;
      cid = result.dataOrNull?.cid;
      dimension = result.dataOrNull?.dimension;
    }
    if (cid == null || cid <= 0) return const Error('该视频暂无可播放分 P');
    return Success((bvid: bvid, cid: cid, dimension: dimension));
  }
}
