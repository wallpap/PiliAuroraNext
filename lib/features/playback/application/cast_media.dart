import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/video_utils.dart';

Future<LoadingState<String?>> loadCastUrl({
  required Account account,
  required int cid,
  required int aid,
  required int? episodeId,
  required int? quality,
}) async {
  final result = await VideoHttp.tvPlayUrl(
    account: account,
    cid: cid,
    objectId: episodeId ?? aid,
    playurlType: episodeId == null ? 1 : 2,
    qn: quality,
  );
  return switch (result) {
    Success(:final response) => switch (response.durl?.firstOrNull?.playUrls) {
      final urls? when urls.isNotEmpty => Success(VideoUtils.getCdnUrl(urls)),
      _ => const Success(null),
    },
    final Error failure => failure,
    final Loading loading => loading,
  };
}
