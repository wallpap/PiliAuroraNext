import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class DisplayPreferences {
  static int get imageQuality => Pref.picQuality;
  static bool get showFanMedals => Pref.showMedal;

  static Future<void> saveImageQuality(int quality) =>
      GStorage.setting.put(SettingBoxKey.defaultPicQa, quality);
}
