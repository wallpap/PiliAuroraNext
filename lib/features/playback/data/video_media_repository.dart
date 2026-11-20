import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/features/playback/domain/playlist/data.dart';
import 'package:pili_aurora_next/features/playback/domain/play_info/data.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class VideoMediaRepository {
  static Future<LoadingState<PlayUrlModel>> fetch({
    required Account account,
    required String bvid,
    required int cid,
    required int? episode,
    required int? season,
    required int quality,
    required bool tryLook,
    required VideoType type,
    required String? language,
    required bool voiceBalance,
    required CancelToken cancelToken,
  }) => VideoHttp.videoUrl(
    account: account,
    bvid: bvid,
    cid: cid,
    epid: episode,
    seasonId: season,
    qn: quality,
    tryLook: tryLook,
    videoType: type,
    language: language,
    voiceBalance: voiceBalance,
    cancelToken: cancelToken,
  );

  static Future<List<VideoItem>> diagnosticsSample() async {
    final result = await VideoHttp.videoUrl(
      cid: 196018899,
      bvid: 'BV1fK4y1t7hj',
      qn: VideoQuality.high1080.code,
      tryLook: false,
      videoType: VideoType.ugc,
    );
    return result.data.dash?.video ?? const [];
  }

  static Future<LoadingState<PlayInfoData>> metadata({
    required Account account,
    required String bvid,
    required int cid,
    int? seasonId,
    int? epId,
  }) => VideoHttp.playInfo(
    account: account,
    bvid: bvid,
    cid: cid,
    seasonId: seasonId,
    epId: epId,
  );

  static Future<LoadingState<MediaListData>> playlist({
    required Account account,
    required Object type,
    required Object id,
    required bool previous,
    Object? anchor,
    int? anchorType,
    required bool descending,
    required Object sortField,
    required bool includeAnchor,
  }) => UserHttp.getMediaList(
    account: account,
    type: type,
    bizId: id,
    ps: 20,
    direction: previous,
    oid: anchor,
    otype: anchorType,
    desc: descending,
    sortField: sortField,
    withCurrent: includeAnchor,
  );

  static Future<LoadingState<void>> recordPlaylistProgress(
    Account account, {
    required int aid,
    required Object listId,
    required bool descending,
  }) => VideoHttp.medialistHistory(
    account: account,
    desc: descending ? 1 : 0,
    oid: aid,
    upperMid: listId,
  );
}
