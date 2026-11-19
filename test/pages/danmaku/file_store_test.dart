import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_protobuf.dart';
import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';
import 'package:pili_aurora_next/generated/bilibili/community/service/dm/v1.pb.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_file_store.dart';
import 'package:pili_aurora_next/pages/danmaku/merge.dart';
import 'package:pili_aurora_next/pages/danmaku/processing_rules.dart';
import 'package:pili_aurora_next/services/danmaku/work_quota.dart';

void main() {
  test('source store reuses ordered run after cancellation and replaces changed input', () async {
    final directory = Directory.systemTemp.createTempSync('pili-sort-reuse-');
    final file = File('${directory.path}/source.pb');
    final store = OrderedDanmakuFileStore(temporaryParent: directory);
    addTearDown(() async {
      await store.dispose();
      file.deleteSync();
      directory.deleteSync();
    });
    await file.writeAsBytes(
      DmSegMobileReply(
        elems: [
          for (var i = 0; i < 600; i++)
            DanmakuElem(content: '$i', progress: 600 - i),
        ],
      ).writeToBuffer(),
    );
    final first = await store.read(file).expand((batch) => batch).toList();
    final runDirectory = directory.listSync().whereType<Directory>().single;
    final sorted = runDirectory.listSync().single as File;
    final sortedStat = sorted.statSync();
    final token = DanmakuWorkToken();
    await expectLater(() async {
      await for (final _ in store.read(file, token: token)) {
        token.cancel();
      }
    }(), throwsA(isA<DanmakuWorkCancelled>()));
    final again = await store.read(file).expand((batch) => batch).toList();
    expect(
      again.map((e) => (e.progress, e.content)),
      first.map((e) => (e.progress, e.content)),
    );
    expect(runDirectory.existsSync(), isTrue);
    expect((sorted.statSync()).modified, sortedStat.modified);
    await file.writeAsBytes(
      DmSegMobileReply(elems: [DanmakuElem(content: 'changed', progress: 99)])
          .writeToBuffer(),
    );
    final changed = await store.read(file).expand((batch) => batch).toList();
    expect(changed.single.content, 'changed');
    expect(runDirectory.existsSync(), isFalse);
    await store.dispose();
    expect(directory.listSync(), [isA<File>()]);
  });

  test(
    'source release waits for the current reader before deleting its run',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pili-sort-release-',
      );
      final file = File('${directory.path}/source.pb');
      await file.writeAsBytes(
        DmSegMobileReply(
          elems: [
            for (var i = 0; i < 600; i++)
              DanmakuElem(content: '$i', progress: 600 - i),
          ],
        ).writeToBuffer(),
      );
      final store = OrderedDanmakuFileStore(temporaryParent: directory);
      Future<void>? releasing;
      await expectLater(() async {
        await for (final _ in store.read(file)) {
          releasing ??= store.dispose();
        }
      }(), throwsA(isA<DanmakuWorkCancelled>()));
      await releasing;
      expect(directory.listSync(), [isA<File>()]);
      file.deleteSync();
      directory.deleteSync();
    },
  );

  test(
    'external runs preserve stable order, merge counts and clean up',
    () async {
      final directory = Directory.systemTemp.createTempSync('pili-sort-test-');
      final file = File('${directory.path}/source.pb');
      final elements = [
        for (var i = 0; i < 900; i++)
          DanmakuElem(
            content: 'text${i % 13}',
            mode: 1,
            progress: (899 - i) % 37 * 1000,
          ),
      ];
      await file.writeAsBytes(
        DmSegMobileReply(elems: elements).writeToBuffer(),
      );
      addTearDown(() {
        file.deleteSync();
        directory.deleteSync();
      });
      final expected = elements.indexed.toList()
        ..sort((a, b) {
          final time = a.$2.progress.compareTo(b.$2.progress);
          return time == 0 ? a.$1.compareTo(b.$1) : time;
        });
      final actual = await readOrderedDanmakuFile(
        file,
        temporaryParent: directory,
      ).expand((b) => b).toList();
      expect(
        actual.map((e) => (e.progress, e.content, e.mode)),
        expected.map((e) => (e.$2.progress, e.$2.content, e.$2.mode)),
      );
      final additions = <DanmakuElement>[];
      await DanmakuWorkQuota.instance.runWithLease(
        64 * 1024 * 1024,
        (lease) => processOrderedDanmakuBatches(
          readOrderedDanmakuFile(file, temporaryParent: directory),
          rules: DanmakuProcessingRules(),
          lease: lease,
          consume: (delta) {
            additions.addAll(delta.additions);
            for (final entry in delta.counts.entries) {
              additions[entry.key].count = entry.value;
            }
          },
        ),
      );
      final merged = DanmakuMerger().merge(
        elements.map(projectDanmakuElement).toList(),
      );
      expect(
        additions.map((e) => (e.progress, e.content, e.count)),
        merged.map((e) => (e.progress, e.content, e.count)),
      );
      expect(directory.listSync(), hasLength(1));
    },
  );

  test('sorted protobuf run preserves the exact element payload', () async {
    final directory = await Directory.systemTemp.createTemp('pili-sort-wire-');
    final source = File('${directory.path}/source.pb');
    final store = OrderedDanmakuFileStore(temporaryParent: directory);
    addTearDown(() async {
      await store.dispose();
      await source.delete();
      await directory.delete();
    });
    const late = [0x10, 2, 0xc2, 0x0c, 3, 1, 2, 3, 0x3a, 1, 0x61];
    const early = [0x10, 0x81, 0, 0x3a, 1, 0x62];
    final original = [10, late.length, ...late, 10, early.length, ...early];
    await source.writeAsBytes(original);

    final elements = await store.read(source).expand((batch) => batch).toList();
    expect(elements.map((element) => element.content), ['b', 'a']);
    final run = directory
        .listSync()
        .whereType<Directory>()
        .single
        .listSync()
        .whereType<File>()
        .single;
    expect(
      await run.readAsBytes(),
      [10, early.length, ...early, 10, late.length, ...late],
    );
    expect(await source.readAsBytes(), original);
  });

  test('cancellation releases sorted runs and keeps original file', () async {
    final directory = Directory.systemTemp.createTempSync('pili-sort-cancel-');
    final file = File('${directory.path}/source.pb');
    await file.writeAsBytes(
      DmSegMobileReply(
        elems: [
          for (var i = 0; i < 600; i++)
            DanmakuElem(content: '$i', progress: 600 - i),
        ],
      ).writeToBuffer(),
    );
    addTearDown(() {
      file.deleteSync();
      directory.deleteSync();
    });
    final token = DanmakuWorkToken();
    await expectLater(() async {
      await for (final _ in readOrderedDanmakuFile(
        file,
        token: token,
        temporaryParent: directory,
      )) {
        token.cancel();
      }
    }(), throwsA(isA<DanmakuWorkCancelled>()));
    expect(directory.listSync(), hasLength(1));
  });
}
