import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/image/src/native_worker_backend.dart';

final nativeWorker = File(
  Platform.environment['REGION_TEST_WORKER'] ??
      'build/probes/image-region/native/Release/piliauroranext_image_worker.exe',
).absolute.path;
final nativeFixtureFile = File(
  Platform.environment['REGION_FIXTURES'] ??
      'build/probes/image-region/fixtures.json',
).absolute;
final nativeFixtureAvailable =
    Platform.isWindows &&
    File(nativeWorker).existsSync() &&
    nativeFixtureFile.existsSync();
final nativeFixtures = nativeFixtureAvailable
    ? ((jsonDecode(nativeFixtureFile.readAsStringSync()) as Map)['images']
              as List)
          .cast<Map>()
    : <Map>[];
final nativeWorkerEvents = <Map<String, Object?>>[];

void observeNativeWorkers() {
  setUp(() {
    nativeWorkerEvents.clear();
    NativeWorkerDecoder.onEvent = nativeWorkerEvents.add;
  });
  tearDown(() => NativeWorkerDecoder.onEvent = null);
}

final _skipReason = _checkNativeFixtures();

String? _checkNativeFixtures() {
  if (nativeFixtureAvailable) return null;
  const prepare = 'python tool/probes/windows/image_region_probe.py';
  final message = Platform.isWindows
      ? 'Windows worker fixtures missing. Run $prepare. '
            'Worker: $nativeWorker; manifest: ${nativeFixtureFile.path}'
      : 'Region worker tests require Windows.';
  if (Platform.environment['REGION_TEST_REQUIRED'] == '1') {
    throw StateError(message);
  }
  return message;
}

void nativeTest(String description, FutureOr<void> Function() body) => test(
  description,
  () => NativeWorkerDecoder.runWith(nativeWorker, body),
  skip: _skipReason,
);

void nativeTestWidgets(String description, WidgetTesterCallback body) =>
    testWidgets(
      description,
      (tester) => NativeWorkerDecoder.runWith(nativeWorker, () => body(tester)),
      skip: _skipReason != null,
    );
