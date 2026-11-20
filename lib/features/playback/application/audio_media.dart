import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/playback/data/audio_media_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart' show Volume;
import 'package:pili_aurora_next/features/playback/application/media_source_selection.dart';

abstract final class AudioMedia {
  static Future<LoadingState<({String url, Volume? volume})>> resolve({
    required int itemType,
    required Int64 oid,
    required List<Int64> subIds,
    required int Function() preferredQuality,
  }) async {
    final source = await AudioMediaRepository.fetch(
      itemType: itemType,
      oid: oid,
      subIds: subIds,
      preferredQuality: preferredQuality,
    );
    return switch (source) {
      Success(:final response) => Success((
        url: MediaSourceSelection.getCdnUrl(response.urls),
        volume: response.volume,
      )),
      Error() => source,
      Loading() => LoadingState.loading(),
    };
  }
}
