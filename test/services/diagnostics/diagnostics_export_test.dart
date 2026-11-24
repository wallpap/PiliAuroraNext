import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Diagnostics diagnostics;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'pili-diagnostics-export-',
    );
    diagnostics = Diagnostics(processReader: () => {'rssBytes': 123456});
    await diagnostics.initialize(directory: directory);
  });
  tearDown(() async {
    diagnostics.dispose();
    await diagnostics.flush();
    await directory.delete(recursive: true);
  });

  test(
    'export coordinates child flush and includes its forwarding status',
    () async {
      final child = Diagnostics();
      await child.initialize(
        directory: Directory('${directory.path}/window-3'),
        childProcess: true,
        windowId: 3,
      );
      child
        ..forwardRecord = ((_) => false)
        ..log(DiagnosticLogLevel.error, 'app', 'queued before snapshot');
      diagnostics
        ..pauseChildren = () async {
          await child.pauseWrites();
          child.log(DiagnosticLogLevel.error, 'app', 'during snapshot');
        }
        ..resumeChildren = (() => Future<void>.sync(child.resumeWrites));
      final exportResult = await diagnostics.exportArchive();
      final archive = exportResult.file;
      try {
        final zip = ZipDecoder().decodeBytes(await archive.readAsBytes());
        final text = utf8.decode(
          zip.files
                  .firstWhere((f) => f.name == 'window-3-runtime.jsonl')
                  .content
              as List<int>,
        );
        expect(text, contains('queued before snapshot'));
        expect(text, isNot(contains('during snapshot')));
        final manifest = jsonDecode(
          utf8.decode(
            zip.files.firstWhere((f) => f.name == 'manifest.json').content
                as List<int>,
          ),
        ) as Map;
        final status = (manifest['children'] as List).single as Map;
        expect((status['storage'] as Map)['forwardingFailures'], 1);
        await child.flushLocal();
        expect(
          await File('${directory.path}/window-3/runtime.jsonl').readAsString(),
          contains('during snapshot'),
        );
      } finally {
        child.dispose();
        await child.flushLocal();
        await exportResult.dispose();
      }
    },
  );

  test(
    'export keeps only one mirrored record and preserves local fallback',
    () async {
      final child = Diagnostics();
      addTearDown(child.dispose);
      final childDirectory = Directory('${directory.path}/window-7');
      await child.initialize(
        directory: childDirectory,
        childProcess: true,
        windowId: 7,
      );
      await (child
            ..forwardRecord = (record) {
              diagnostics.receiveRecord(record, windowId: 7);
              return true;
            }
            ..log(DiagnosticLogLevel.error, 'app', {
              'message': 'mirrored',
              'token': 'fixture-secret',
            })
            ..forwardRecord = null
            ..log(DiagnosticLogLevel.error, 'app', 'local fallback'))
          .flushLocal();

      final export = await diagnostics.exportArchive();
      addTearDown(export.dispose);
      final zip = ZipDecoder().decodeBytes(await export.file.readAsBytes());
      String read(String name) => utf8.decode(
        zip.files.singleWhere((file) => file.name == name).content,
      );
      final main = jsonDecode(read('runtime.jsonl')) as Map;
      expect(main['message'], {'message': 'mirrored', 'token': '<redacted>'});
      final fallback = jsonDecode(read('window-7-runtime.jsonl')) as Map;
      expect(fallback['message'], 'local fallback');
      final manifest = jsonDecode(read('manifest.json')) as Map;
      expect(manifest['export'], {'skippedRecords': 0, 'duplicateRecords': 1});
      expect(
        await File('${childDirectory.path}/runtime.jsonl').readAsLines(),
        hasLength(2),
      );
    },
  );

  test('failed child coordination resumes writes and permits retry', () async {
    var resumes = 0;
    diagnostics
      ..pauseChildren = (() => Future<void>.error(StateError('not connected')))
      ..resumeChildren = () async {
        resumes++;
      };
    await expectLater(
      diagnostics.exportArchive(),
      _exportFailure(
        DiagnosticExportStage.snapshot,
        isA<StateError>(),
      ),
    );
    expect(resumes, 1);
    diagnostics.log(DiagnosticLogLevel.error, 'app', 'after failure');
    await diagnostics.flushLocal();
    expect(
      await File('${directory.path}/runtime.jsonl').readAsString(),
      contains('after failure'),
    );
    diagnostics.pauseChildren = null;
    final exportResult = await diagnostics.exportArchive();
    await exportResult.dispose();
  });

  test('resume failure preserves the original snapshot failure', () async {
    final primary = StateError('snapshot failed');
    diagnostics
      ..pauseChildren = (() => Future<void>.error(primary))
      ..resumeChildren = (() =>
          Future<void>.error(StateError('resume failed')));
    await expectLater(
      diagnostics.exportArchive(),
      _exportFailure(
        DiagnosticExportStage.snapshot,
        same(primary),
      ),
    );
    diagnostics.log(DiagnosticLogLevel.error, 'app', 'writes resumed');
    await diagnostics.flush().timeout(const Duration(seconds: 1));
    expect(
      await File('${directory.path}/runtime.jsonl').readAsString(),
      contains('writes resumed'),
    );
  });

  test('export manifest reports skipped malformed records', () async {
    final raw = File('${directory.path}/runtime.jsonl');
    await raw.writeAsString(
      '${jsonEncode({'channel': 'runtime', 'message': 'keep this'})}\n'
      'incomplete record\n',
    );
    final exportResult = await diagnostics.exportArchive();
    final archive = exportResult.file;
    try {
      final zip = ZipDecoder().decodeBytes(await archive.readAsBytes());
      final manifest = jsonDecode(
        utf8.decode(
          zip.files.firstWhere((f) => f.name == 'manifest.json').content,
        ),
      ) as Map;
      expect(manifest['export'], containsPair('skippedRecords', 1));
      expect(exportResult.skippedRecords, 1);
      expect(await raw.readAsString(), contains('incomplete record'));
    } finally {
      await exportResult.dispose();
    }
  });

  test(
    'uncoordinated child files are preserved and marked in export',
    () async {
      final childDirectory = Directory('${directory.path}/window-9');
      await childDirectory.create();
      final file = File('${childDirectory.path}/runtime.jsonl');
      await file.writeAsString('offline record');
      diagnostics.pauseChildren = () async {
        diagnostics.skippedChildWindows.add(9);
      };
      final exportResult = await diagnostics.exportArchive();
      final archive = exportResult.file;
      try {
        final zip = ZipDecoder().decodeBytes(await archive.readAsBytes());
        expect(
          zip.files.map((file) => file.name),
          isNot(contains('window-9-runtime.jsonl')),
        );
        final manifest = jsonDecode(
          utf8.decode(
            zip.files.firstWhere((file) => file.name == 'manifest.json').content
                as List<int>,
          ),
        ) as Map;
        expect((manifest['storage'] as Map)['skippedChildWindows'], [9]);
        await diagnostics.clear();
        expect(await file.readAsString(), 'offline record');
      } finally {
        await exportResult.dispose();
      }
    },
  );

  test(
    'export result owns stable completeness metadata and temporary files',
    () async {
      diagnostics
        ..pauseChildren = () async {
          diagnostics.skippedChildWindows.add(9);
        }
        ..resumeChildren = () async {
          diagnostics.skippedChildWindows.clear();
        }
        ..log(DiagnosticLogLevel.error, 'app', 'original stays local');
      final result = await diagnostics.exportArchive();
      try {
        expect(diagnostics.skippedChildWindows, isEmpty);
        expect(result.skippedChildWindows, {9});
        expect(result.skippedRecords, 0);
        expect(
          () => result.skippedChildWindows.add(10),
          throwsUnsupportedError,
        );
        expect(result.file.existsSync(), isTrue);
      } finally {
        await result.dispose();
      }
      await result.dispose();
      expect(result.file.parent.existsSync(), isFalse);
      expect(File('${directory.path}/runtime.jsonl').existsSync(), isTrue);
    },
  );

  test('unavailable temporary storage reports the prepare stage', () async {
    final blocked = File('${directory.path}/blocked-temp');
    await blocked.writeAsString('keep');
    await IOOverrides.runZoned(() async {
      await expectLater(
        diagnostics.exportArchive(),
        _exportFailure(
          DiagnosticExportStage.prepare,
          isA<FileSystemException>(),
        ),
      );
    }, getSystemTempDirectory: () => Directory(blocked.path));
    expect(await blocked.readAsString(), 'keep');
  });

  test('snapshot failure removes raw temporary copies', () async {
    final temporary = await Directory('${directory.path}/export-temp').create();
    diagnostics
      ..log(DiagnosticLogLevel.error, 'app', 'keep original')
      ..register('app', () => throw StateError('source failed'));
    await IOOverrides.runZoned(() async {
      await expectLater(
        diagnostics.exportArchive(),
        _exportFailure(
          DiagnosticExportStage.snapshot,
          isA<StateError>(),
        ),
      );
    }, getSystemTempDirectory: () => temporary);
    expect(await temporary.list().toList(), isEmpty);
    expect(File('${directory.path}/runtime.jsonl').existsSync(), isTrue);
  });

  test(
    'archive failure preserves its cause and removes temporary copies',
    () async {
      final temporary = await Directory('${directory.path}/export-temp')
          .create();
      diagnostics
        ..log(DiagnosticLogLevel.error, 'app', 'keep original')
        ..resumeChildren = () async {
          final snapshot =
              (await temporary.list().toList()).single as Directory;
          await File('${snapshot.path}/manifest.json').delete();
        };
      await IOOverrides.runZoned(() async {
        await expectLater(
          diagnostics.exportArchive(),
          _exportFailure(
            DiagnosticExportStage.archive,
            isA<FileSystemException>(),
          ),
        );
      }, getSystemTempDirectory: () => temporary);
      expect(await temporary.list().toList(), isEmpty);
      diagnostics
        ..resumeChildren = null
        ..log(DiagnosticLogLevel.error, 'app', 'after archive failure');
      await diagnostics.flush().timeout(const Duration(seconds: 1));
      expect(
        await File('${directory.path}/runtime.jsonl').readAsString(),
        contains('after archive failure'),
      );
    },
  );

  test('pause flush failure immediately restores writes', () async {
    final failing = _FailingPauseDiagnostics();
    final target = Directory('${directory.path}/pause-failure');
    await failing.initialize(directory: target);
    failing.failNextFlush = true;
    try {
      await expectLater(
        failing.exportArchive(),
        _exportFailure(
          DiagnosticExportStage.snapshot,
          isA<StateError>(),
        ),
      );
      failing.log(DiagnosticLogLevel.error, 'app', 'after failed pause');
      await failing.flush().timeout(const Duration(seconds: 1));
      expect(
        await File('${target.path}/runtime.jsonl').readAsString(),
        contains('after failed pause'),
      );
    } finally {
      failing.dispose();
      await failing.flushLocal();
    }
  });

  test(
    'export contains readable sanitized logs and performance records',
    () async {
      await diagnostics.configure(
        tracing: true,
        level: DiagnosticLogLevel.debug,
      );
      diagnostics.log(
        DiagnosticLogLevel.debug,
        'test',
        "token=export-secret-test\nAudio 'track.m4s?e=export-signed-query&mid=export-user-id' (aac)",
      );
      final mutable = {
        'token': 'snapshot-secret',
        '${'x' * 100}Token': 'long-key-secret',
      };
      diagnostics
        ..register('player', () => {'nested': mutable})
        ..capture();
      mutable['token'] = 'later-value';
      expect(jsonEncode(diagnostics.latest), contains('snapshot-secret'));
      await diagnostics.flush();
      final raw = await File('${directory.path}/runtime.jsonl').readAsString();
      expect(raw, contains('export-secret-test'));
      final childDir = Directory('${directory.path}/window-9');
      await childDir.create();
      await File('${childDir.path}/runtime.jsonl').writeAsString(
        '${jsonEncode({
          'channel': 'runtime',
          'message': {'deviceId': 'child-device-secret'},
          'details': {'token': 'child-token-secret'},
        })}\ninvalid partial line',
      );
      await File('${childDir.path}/status.json')
          .writeAsString(jsonEncode({'token': 'child-status-secret'}));
      final exportResult = await diagnostics.exportArchive();
      final file = exportResult.file;
      try {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        expect(
          archive.files.map((file) => file.name),
          containsAll(['runtime.jsonl', 'performance.jsonl', 'manifest.json']),
        );
        expect(
          await File('${directory.path}/runtime.jsonl').readAsString(),
          raw,
        );
        for (final entry in archive.files) {
          final content = utf8.decode(entry.content);
          for (final secret in [
            'snapshot-secret',
            'long-key-secret',
            'child-device-secret',
            'child-token-secret',
            'child-status-secret',
          ]) {
            expect(content, isNot(contains(secret)));
          }
          expect(content, isNot(contains('export-secret-test')));
          expect(content, isNot(contains('export-signed-query')));
          expect(content, isNot(contains('export-user-id')));
          for (final line in const LineSplitter().convert(content)) {
            expect(jsonDecode(line), isA<Map>());
          }
        }
      } finally {
        await exportResult.dispose();
      }
    },
  );
}

class _FailingPauseDiagnostics extends Diagnostics {
  bool failNextFlush = false;
  @override
  Future<void> flushLocal() {
    if (failNextFlush) {
      failNextFlush = false;
      return Future<void>.error(StateError('pause flush failed'));
    }
    return super.flushLocal();
  }
}

Matcher _exportFailure(DiagnosticExportStage stage, Matcher cause) => throwsA(
  isA<DiagnosticExportException>()
      .having((error) => error.stage, 'stage', stage)
      .having((error) => error.cause, 'cause', cause),
);
