import 'package:pili_aurora_next/models/common/video/cdn_type.dart';
import 'package:pili_aurora_next/models/common/video/subtitle_pref_type.dart';
import 'package:pili_aurora_next/models/common/video/video_decode_type.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class VideoPreferences {
  static bool get autoplay => Pref.autoPlayEnable;
  static bool get openCommentsFirst => Pref.defaultShowComment;
  static bool get resumeLastPart => Pref.continuePlayingPart;
  static SubtitlePrefType get subtitle => Pref.subtitlePreferenceV2;
  static bool get inheritSubtitle => Pref.inheritSubtitleState;
  static bool get showAiSummary => Pref.enableAi;

  static int qualityCode({bool wifi = true}) =>
      wifi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;

  static List<VideoDecodeFormatType> codecs({bool wifi = true}) =>
      wifi ? Pref.preferCodecs : Pref.preferCodecsCellular;

  static bool get likeOnCoin => Pref.coinWithLike;

  static Future<void> saveLikeOnCoin(bool value) =>
      GStorage.setting.put(SettingBoxKey.coinWithLike, value);

  static CDNService get cdn => Pref.defaultCDNService;
  static bool get bypassAudioCdnRewrite => Pref.disableAudioCDN;
  static bool get enableCdnFallback => Pref.enableMultiCdn;
  static List<CDNService> get cdnFallbackOrder => Pref.cdnFallbackOrder;

  static Future<void> saveCdn(CDNService value) =>
      GStorage.setting.put(SettingBoxKey.CDNService, value.name);
}
