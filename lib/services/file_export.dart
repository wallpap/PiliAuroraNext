import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';

Future<bool> exportFile({
  required String name,
  required Uint8List bytes,
}) async {
  final path = await FilePicker.saveFile(
    fileName: name,
    bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
  );
  if (path == null) return false;
  if (PlatformUtils.isDesktop) {
    await File(path.toFilePath()).writeAsBytes(bytes);
  }
  return true;
}
