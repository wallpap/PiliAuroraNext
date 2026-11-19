import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

abstract final class AuthorFilterPreferences {
  static bool _enabled(String key) => switch (GStorage.setting.get(key)) {
    final bool value => value,
    _ => true,
  };

  static bool get filterBlockedAuthors =>
      _enabled(SettingBoxKey.filterBlockedAuthors);

  static bool get checkCooperativeAuthors =>
      _enabled(SettingBoxKey.checkCooperativeAuthors);
}
