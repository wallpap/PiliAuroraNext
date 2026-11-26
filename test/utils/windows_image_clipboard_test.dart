import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/platform/desktop/windows_image_clipboard.dart';
import 'package:pili_aurora_next/platform/files/path_actions.dart';

const _channel = MethodChannel('piliauroranext/image_clipboard');
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DQAAAEgQGALFXOsAAAAABJRU5ErkJggg==';
const _gif =
    'R0lGODlhAQABAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAQABAAAIBAABBAQAIfkEARQAAQAsAAAAAAEAAQCBAAD/AAAAAAAAAAAACAQAAQQEADs=';
const _apng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAABAAAAAQAAAAAAAAAAAAEACgAAWn8w0AAAAA1JREFUeJxj+M/A0AAABIEBgCxVzrAAAAAaZmNUTAAAAAEAAAABAAAAAQAAAAAAAAAAAAEABQAAylCdOQAAABFmZEFUAAAAAnicY2Bg+P8fAAMCAf/1e6XXAAAAAElFTkSuQmCC';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('image-clipboard-test-');
    tmpDirPath = directory.path;
  });
  tearDownAll(() => directory.delete(recursive: true));
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('copies a static PNG as an image with transparency', () async {
    final bytes = base64Decode(_png);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return null;
    });

    expect(await WindowsImageClipboard.write(bytes), isFalse);
    expect(calls.single.method, 'writeBitmap');
    expect(calls.single.arguments, {
      'png': bytes,
      'pixels': [255, 0, 0, 128],
      'width': 1,
      'height': 1,
    });
  });

  final animations = {
    'gif': () => Future.value(base64Decode(_gif)),
    'png': () => Future.value(base64Decode(_apng)),
    'webp': () =>
        File('test/common/widgets/image/fixtures/animated.webp').readAsBytes(),
  };
  for (final MapEntry(key: extension, value: loadBytes) in animations.entries) {
    test('copies animated $extension as the unchanged original file', () async {
      final bytes = await loadBytes();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return null;
      });

      expect(await WindowsImageClipboard.write(bytes), isTrue);
      expect(calls.single.method, 'writeFile');
      final file = File(calls.single.arguments['path'] as String);
      expect(file.path, endsWith('.$extension'));
      expect(await file.readAsBytes(), bytes);
      expect(calls.single.arguments['gif'], extension == 'gif' ? bytes : null);
    });
  }

  test('removes the staged file if the clipboard write fails', () async {
    late File stagedFile;
    messenger.setMockMethodCallHandler(_channel, (call) {
      stagedFile = File(call.arguments['path'] as String);
      expect(stagedFile.existsSync(), isTrue);
      return Future.error(PlatformException(code: 'clipboard_write_failed'));
    });

    await expectLater(
      WindowsImageClipboard.write(base64Decode(_gif)),
      throwsA(isA<PlatformException>()),
    );
    expect(stagedFile.existsSync(), isFalse);
  });
}
