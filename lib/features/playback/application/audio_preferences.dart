import 'package:pili_aurora_next/features/playback/domain/media/audio_quality.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class AudioPreferences {
  static PlayRepeat get playMode => Pref.audioPlayMode;
  static double get desktopVolume => Pref.desktopVolume;
  static double get mobileVolumePercent => Pref.playerVolume;
  static double get maxDesktopVolume => Pref.maxVolume;
  static int qualityCode({bool wifi = true}) =>
      wifi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular;

  static Map<String, String> playerOptions({
    required bool android,
    double? desktopVolumePercent,
  }) => {
    if (android) 'ao': Pref.audioOutput,
    'volume':
        desktopVolumePercent?.toStringAsFixed(0) ??
        mobileVolumePercent.toString(),
    ...Pref.initBuffer(),
  };

  static Future<void> savePlayMode(PlayRepeat mode) =>
      GStorage.setting.put(SettingBoxKey.audioPlayMode, mode.index);

  static Future<void> saveMobileVolumePercent(double percent) =>
      GStorage.setting.put(SettingBoxKey.playerVolume, percent);

  static Future<void> saveDesktopVolumeRatio(double ratio) =>
      GStorage.setting.put(SettingBoxKey.desktopVolume, ratio);

  static Future<void> saveQuality(AudioQuality quality, {required bool wifi}) =>
      GStorage.setting.put(
        wifi
            ? SettingBoxKey.defaultAudioQa
            : SettingBoxKey.defaultAudioQaCellular,
        quality.code,
      );
}
