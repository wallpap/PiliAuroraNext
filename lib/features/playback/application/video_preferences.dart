import 'package:pili_aurora_next/models/common/video/cdn_type.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class VideoPreferences {
  static bool get likeOnCoin => Pref.coinWithLike;

  static Future<void> saveLikeOnCoin(bool value) =>
      GStorage.setting.put(SettingBoxKey.coinWithLike, value);

  static CDNService get cdn => Pref.defaultCDNService;

  static Future<void> saveCdn(CDNService value) =>
      GStorage.setting.put(SettingBoxKey.CDNService, value.name);
}
