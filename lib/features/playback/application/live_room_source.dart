import 'package:pili_aurora_next/models/remote/live/live_room_play_info/codec.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/stream.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_source.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/video_utils.dart';

class LiveRoomSource {
  const LiveRoomSource._({
    required this.streams,
    required this.streamIndex,
    required this.formatIndex,
    required this.codecIndex,
    required this.liveUrlIndex,
    required this.codec,
    required this.source,
  });

  final List<Stream> streams;
  final int streamIndex;
  final int formatIndex;
  final int codecIndex;
  final int liveUrlIndex;
  final CodecItem codec;
  final NetworkSource source;

  factory LiveRoomSource.preferred(List<Stream> streams) {
    final preference = Pref.liveStream;
    ({int stream, int format, int codec})? fallback;
    for (final (streamIndex, stream) in streams.indexed) {
      for (final (formatIndex, format) in stream.format.indexed) {
        for (final (codecIndex, codec) in format.codec.indexed) {
          if (codec.urlInfo.isEmpty) continue;
          fallback ??= (
            stream: streamIndex,
            format: formatIndex,
            codec: codecIndex,
          );
          if (preference == null ||
              preference.length != 3 ||
              (stream.protocolName == preference[0] &&
                  format.formatName == preference[1] &&
                  codec.codecName == preference[2])) {
            return LiveRoomSource.select(
              streams,
              streamIndex: streamIndex,
              formatIndex: formatIndex,
              codecIndex: codecIndex,
              liveUrlIndex: 0,
            );
          }
        }
      }
    }
    if (fallback == null) throw const FormatException('直播响应缺少可用线路');
    return LiveRoomSource.select(
      streams,
      streamIndex: fallback.stream,
      formatIndex: fallback.format,
      codecIndex: fallback.codec,
      liveUrlIndex: 0,
    );
  }

  factory LiveRoomSource.select(
    List<Stream> streams, {
    required int streamIndex,
    required int formatIndex,
    required int codecIndex,
    required int liveUrlIndex,
  }) {
    if (streamIndex < 0 || streamIndex >= streams.length) {
      throw const FormatException('直播线路已失效');
    }
    final formats = streams[streamIndex].format;
    if (formatIndex < 0 || formatIndex >= formats.length) {
      throw const FormatException('直播格式已失效');
    }
    final codecs = formats[formatIndex].codec;
    if (codecIndex < 0 || codecIndex >= codecs.length) {
      throw const FormatException('直播编码已失效');
    }
    final item = codecs[codecIndex];
    if (liveUrlIndex < 0 || liveUrlIndex >= item.urlInfo.length) {
      throw const FormatException('直播地址已失效');
    }
    final urls = VideoUtils.getLiveCdnUrls(item, index: liveUrlIndex);
    return LiveRoomSource._(
      streams: streams,
      streamIndex: streamIndex,
      formatIndex: formatIndex,
      codecIndex: codecIndex,
      liveUrlIndex: liveUrlIndex,
      codec: item,
      source: NetworkSource(
        videoSource: urls.first,
        audioSource: null,
        videoCandidates: urls,
      ),
    );
  }

  Future<void> remember() => GStorage.setting.put(SettingBoxKey.liveStream, [
    streams[streamIndex].protocolName,
    streams[streamIndex].format[formatIndex].formatName,
    codec.codecName,
  ]);
}
