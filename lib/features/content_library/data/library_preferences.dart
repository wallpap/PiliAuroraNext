import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

class LibraryPreferences {
  bool get playAll => Pref.enablePlayAll;
  Stream<void> get changes =>
      GStorage.setting.watch(key: SettingBoxKey.enablePlayAll);
  Future<void> savePlayAll(bool value) =>
      GStorage.setting.put(SettingBoxKey.enablePlayAll, value);
}
