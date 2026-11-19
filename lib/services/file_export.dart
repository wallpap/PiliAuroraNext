import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';

Future<bool> exportFile({
  required String name,
  required Uint8List bytes,
  required List<String> allowedExtensions,
  FileType type = FileType.custom,
}) async {
  final path = await FilePicker.saveFile(
    allowedExtensions: allowedExtensions,
    type: type,
    fileName: name,
    bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
  );
  if (path == null) return false;
  if (PlatformUtils.isDesktop) {
    await File(path.toFilePath()).writeAsBytes(bytes);
  }
  return true;
}
