import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/playback/data/video_media_repository.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/features/playback/domain/play_info/data.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

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

  Future<LoadingState<PlayUrlModel>> fetch(int quality) =>
      VideoMediaRepository.fetch(
        account: account,
        bvid: bvid,
        cid: cid,
        episode: episode,
        season: season,
        quality: quality,
        tryLook: tryLook,
        type: type,
        language: language,
        voiceBalance: voiceBalance,
        cancelToken: _token,
      );

  static Future<LoadingState<PlayInfoData>?> metadata({
    required String bvid,
    required int cid,
    int? seasonId,
    int? epId,
    AccountScope? owner,
  }) async {
    final scope = owner ?? AccountScope.capture();
    if (!scope.isCurrent) return null;
    final result = await VideoMediaRepository.metadata(
      account: scope.account,
      bvid: bvid,
      cid: cid,
      seasonId: seasonId,
      epId: epId,
    );
    return scope.isCurrent ? result : null;
  }
}
