import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class AudioPreferences {
  static PlayRepeat get playMode => Pref.audioPlayMode;

  static Future<void> savePlayMode(PlayRepeat mode) =>
      GStorage.setting.put(SettingBoxKey.audioPlayMode, mode.index);

  static Future<void> saveMobileVolumePercent(double percent) =>
      GStorage.setting.put(SettingBoxKey.playerVolume, percent);

  static Future<void> saveDesktopVolumeRatio(double ratio) =>
      GStorage.setting.put(SettingBoxKey.desktopVolume, ratio);
}
