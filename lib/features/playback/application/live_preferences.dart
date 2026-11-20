import 'package:pili_aurora_next/features/playback/domain/live/super_chat_type.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class LivePreferences {
  static int get desktopQuality => Pref.liveQuality;
  static SuperChatType get superChat => Pref.superChatType;
  static double get fullScreenSuperChatWidth => Pref.fullScreenSCWidth;
  static String? get cdnHost => Pref.liveCdnUrl;

  static Future<void> saveCdnHost(String? value) => value == null
      ? GStorage.setting.delete(SettingBoxKey.liveCdnUrl)
      : GStorage.setting.put(SettingBoxKey.liveCdnUrl, value);
}
