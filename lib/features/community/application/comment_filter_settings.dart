import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class CommentFilterSettings {
  static String get keywords => Pref.banWordForReply;

  static Future<bool> appendKeyword(String expected, String addition) async {
    if (keywords != expected) return false;
    final pattern = expected + addition;
    RegExp(pattern, caseSensitive: false);
    await GStorage.setting.put(SettingBoxKey.banWordForReply, pattern);
    return true;
  }
}
