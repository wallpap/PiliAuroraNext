import 'package:pili_aurora_next/services/settings/settings_backup.dart';
import 'package:pili_aurora_next/utils/storage.dart';

abstract final class ApplicationSettings {
  static SettingsBackup get backup =>
      SettingsBackup(setting: GStorage.setting, video: GStorage.video);

  static Future<void> reset({required bool includeAccounts}) async {
    if (includeAccounts) {
      await GStorage.clear();
    } else {
      await Future.wait([GStorage.setting.clear(), GStorage.video.clear()]);
    }
  }
}
