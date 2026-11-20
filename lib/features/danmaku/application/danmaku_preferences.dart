import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

final danmakuFrameRateProvider = Provider.autoDispose<int>((ref) {
  final changes = GStorage.setting
      .watch(key: SettingBoxKey.danmakuFrameRate)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return DanmakuPreferences.frameRate;
});

abstract final class DanmakuPreferences {
  static int get frameRate => Pref.danmakuFrameRate;
  static bool get scaleRepeats => Pref.mergeDanmakuScale;
  static int get repeatThreshold => Pref.mergeDanmakuThreshold;
  static double get repeatLogBase => Pref.mergeDanmakuLogBase;

  static Stream<void> get filterChanges => GStorage.setting
      .watch()
      .where(
        (event) => const {
          SettingBoxKey.mergeDanmaku,
          SettingBoxKey.mergeDanmakuScale,
          SettingBoxKey.mergeDanmakuThreshold,
          SettingBoxKey.mergeDanmakuLogBase,
          SettingBoxKey.showVipDanmaku,
        }.contains(event.key),
      )
      .map((_) {});

  static Future<void> saveFrameRate(int value) =>
      GStorage.setting.put(SettingBoxKey.danmakuFrameRate, value);

  static Future<void> saveRepeatThreshold(int value) =>
      GStorage.setting.put(SettingBoxKey.mergeDanmakuThreshold, value);

  static Future<void> saveRepeatLogBase(double value) =>
      GStorage.setting.put(SettingBoxKey.mergeDanmakuLogBase, value);
}
