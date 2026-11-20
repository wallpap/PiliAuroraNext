import 'package:pili_aurora_next/services/settings/webdav_client.dart';
import 'package:pili_aurora_next/features/account/data/credential_cipher.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

typedef WebDavConfiguration = ({
  String uri,
  String username,
  String password,
  String directory,
});

abstract final class WebDavPreferences {
  static WebDavConfiguration read() => (
    uri: Pref.webdavUri,
    username: Pref.webdavUsername,
    password: Pref.webdavPassword,
    directory: Pref.webdavDirectory,
  );

  static Future<void> save(WebDavConfiguration draft) async {
    final uri = draft.uri.trim();
    if (draft.username.contains(':')) {
      throw ArgumentError('WebDAV Basic Auth 用户名不能包含冒号');
    }
    if (uri.isNotEmpty) {
      WebDavSettingsClient.validateEndpoint(
        Uri.parse(uri),
        allowInsecureLoopback: true,
      );
    }
    await GStorage.setting.putAll({
      SettingBoxKey.webdavUri: uri,
      SettingBoxKey.webdavUsername: draft.username,
      SettingBoxKey.webdavPassword: CredentialCipher.encrypt(draft.password),
      SettingBoxKey.webdavDirectory: draft.directory,
    });
  }
}
