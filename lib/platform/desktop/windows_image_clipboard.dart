import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, instantiateImageCodec;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:pili_aurora_next/platform/files/path_actions.dart';

abstract final class WindowsImageClipboard {
  static const _channel = MethodChannel('piliauroranext/image_clipboard');

  /// 返回是否以原文件形式复制；动画不同时发布单帧位图，避免接收方优先读取静态帧。
  static Future<bool> write(Uint8List bytes) async {
    final mime = lookupMimeType('', headerBytes: bytes);
    final header = ByteData.sublistView(bytes);
    if (mime == 'image/gif') {
      await _writeFile(bytes, 'gif');
      return true;
    }
    if (mime == 'image/webp' &&
        bytes.length > 20 &&
        header.getUint32(12) == 0x56503858 &&
        (bytes[20] & 0x02) != 0) {
      await _writeFile(bytes, 'webp');
      return true;
    }
    if (mime == 'image/png' && _isAnimatedPng(header)) {
      await _writeFile(bytes, 'png');
      return true;
    }

    final codec = await instantiateImageCodec(bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final pixels = await image.toByteData(
          format: ImageByteFormat.rawStraightRgba,
        );
        final png = mime == 'image/png'
            ? bytes
            : (await image.toByteData(format: ImageByteFormat.png))?.buffer
                  .asUint8List();
        if (pixels == null || png == null) {
          throw StateError('Image encoding failed');
        }
        await _channel.invokeMethod<void>('writeBitmap', {
          'width': image.width,
          'height': image.height,
          'pixels': pixels.buffer.asUint8List(
            pixels.offsetInBytes,
            pixels.lengthInBytes,
          ),
          'png': png,
        });
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
    return false;
  }

  static bool _isAnimatedPng(ByteData bytes) {
    for (var offset = 8; offset + 12 <= bytes.lengthInBytes;) {
      final length = bytes.getUint32(offset);
      final type = bytes.getUint32(offset + 4);
      if (length > bytes.lengthInBytes - offset - 12) return false;
      if (type == 0x6163544c && length == 8) return true;
      if (type == 0x49444154 || type == 0x49454e44) return false;
      offset += length + 12;
    }
    return false;
  }

  static Future<void> _writeFile(Uint8List bytes, String extension) async {
    final root = Directory(path.join(tmpDirPath, 'image-clipboard'));
    await root.create(recursive: true);
    final directory = await root.createTemp(
      'image-${DateTime.now().millisecondsSinceEpoch}-',
    );
    try {
      final file = await File(path.join(directory.path, '图片.$extension'))
          .writeAsBytes(bytes);
      await _channel.invokeMethod<void>('writeFile', {
        'path': file.absolute.path,
        if (extension == 'gif') 'gif': bytes,
      });
    } catch (_) {
      await _delete(directory);
      rethrow;
    }
    unawaited(_prune(root, directory.path));
  }

  static Future<void> _prune(Directory root, String currentPath) async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! Directory || entry.path == currentPath) continue;
        final name = path.basename(entry.path).split('-');
        if (name.length != 3 || name.first != 'image') continue;
        final createdAt = int.tryParse(name[1]);
        if (createdAt != null && createdAt < cutoff) await _delete(entry);
      }
    } on FileSystemException {
      return;
    }
  }

  static Future<void> _delete(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }
}
