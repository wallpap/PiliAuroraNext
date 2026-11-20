import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/common/video/video_quality.dart';
import 'package:pili_aurora_next/models/common/video/video_type.dart';
import 'package:pili_aurora_next/models/remote/media_list/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_play_info/data.dart';
import 'package:pili_aurora_next/models/video/play/url.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final class VideoMediaQuery {
  VideoMediaQuery({
    required this.account,
    required this.bvid,
    required this.cid,
    required this.episode,
    required this.season,
    required this.type,
    required this.tryLook,
    required this.voiceBalance,
    this.language,
  });

  final Account account;
  final String bvid;
  final int cid;
  final int? episode, season;
  final VideoType type;
  final bool tryLook, voiceBalance;
  final String? language;
  final _token = CancelToken();

  bool get isCancelled => _token.isCancelled;
  void cancel() => _token.cancel();

  Future<LoadingState<PlayUrlModel>> fetch(int quality) => VideoHttp.videoUrl(
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
    cancelToken: _token,
  );
}

abstract final class VideoMediaRepository {
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
    required String bvid,
    required int cid,
    int? seasonId,
    int? epId,
  }) =>
      VideoHttp.playInfo(bvid: bvid, cid: cid, seasonId: seasonId, epId: epId);

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
