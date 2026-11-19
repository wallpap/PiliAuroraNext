import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/grpc/audio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/video/play/url.dart' show Volume;
import 'package:pili_aurora_next/utils/extension/iterable_ext.dart';

typedef AudioMediaSource = ({List<String> urls, Volume? volume});

abstract final class AudioMediaRepository {
  static Future<LoadingState<AudioMediaSource>> fetch({
    required int itemType,
    required Int64 oid,
    required List<Int64> subIds,
    required int Function() preferredQuality,
  }) async {
    final result = await AudioGrpc.audioPlayUrl(
      itemType: itemType,
      oid: oid,
      subId: subIds,
    );
    if (result case Error()) return result;
    if (!result.isSuccess) return LoadingState.loading();

    final info = result.data.playerInfo.values.firstOrNull;
    if (info == null) throw const FormatException('响应缺少音频信息');
    final Iterable<String> urls;
    if (info.hasPlayDash()) {
      if (info.playDash.audio.isEmpty) throw const FormatException('响应缺少音频来源');
      final quality = preferredQuality();
      final audio = info.playDash.audio.findClosestTarget(
        (item) => item.id <= quality,
        (first, second) => first.id > second.id ? first : second,
      );
      urls = [audio.baseUrl, ...audio.backupUrl];
    } else if (info.hasPlayUrl() && info.playUrl.durl.isNotEmpty) {
      final audio = info.playUrl.durl.first;
      urls = [audio.url, ...audio.backupUrl];
    } else {
      throw const FormatException('响应缺少音频来源');
    }
    final volume = info.volume;
    return Success((
      urls: List.unmodifiable(urls),
      volume: !info.hasVolume()
          ? null
          : Volume(
              measuredI: volume.measuredI,
              measuredLra: volume.measuredLra,
              measuredTp: volume.measuredTp,
              measuredThreshold: volume.measuredThreshold,
              targetOffset: volume.targetOffset,
              targetI: volume.targetI,
              targetTp: volume.targetTp,
            ),
    ));
  }
}
