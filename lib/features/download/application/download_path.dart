import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

String? _downloadPath;
Future<String>? _resolvingDownloadPath;

String get downloadPath {
  if (_downloadPath case final current?) return current;
  final configured = Pref.downloadPath;
  return configured != null && configured.isNotEmpty
      ? configured
      : defDownloadPath;
}

set downloadPath(String value) => _downloadPath = value;

Future<String> resolveDownloadPath() {
  if (_downloadPath case final current?) return Future.value(current);
  return _resolvingDownloadPath ??= _resolveDownloadPath()
      .then((value) => downloadPath = value)
      .whenComplete(() => _resolvingDownloadPath = null);
}

Future<String> _resolveDownloadPath() async {
  if (PlatformUtils.isDesktop) {
    final configured = Pref.downloadPath;
    if (configured != null && configured.isNotEmpty) {
      try {
        await Directory(configured).create(recursive: true);
        return configured;
      } on FileSystemException catch (error, stack) {
        await GStorage.setting.delete(SettingBoxKey.downloadPath);
        logger.w('下载目录无效，已恢复默认目录', error: error.runtimeType, stackTrace: stack);
      }
    }
  } else if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      return path.join(external.path, PathUtils.downloadDir);
    }
  }
  return defDownloadPath;
}
