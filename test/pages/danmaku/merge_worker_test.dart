import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_rule.dart';
import 'package:pili_aurora_next/features/danmaku/domain/processing_budget.dart';
import 'package:pili_aurora_next/pages/danmaku/merge.dart';
import 'package:pili_aurora_next/pages/danmaku/processing_rules.dart';
import 'package:pili_aurora_next/services/danmaku/work_quota.dart';

DanmakuElement _dm(
  String text,
  int time, {
  int mode = 1,
  bool self = false,
  int pool = 0,
}) => DanmakuElement(
  content: text,
  progress: time,
  mode: mode,
  isSelf: self,
  pool: pool,
);

void main() {
  test(
    'worker preserves maximum merged weight across batch boundaries',
    () async {
      final input = [
        _dm('相同弹幕', 0)..weight = 1,
        for (var i = 1; i < 300; i++) _dm('独立内容$i', i, self: true),
        _dm('相同弹幕', 1000)..weight = 11,
      ];
      final result = await mergeDanmakuInBackground(input);
      expect(result.first.count, 2);
      expect(result.first.weight, 11);
      expect(result.first.progress, 0);
    },
  );

  test('ordered worker cancellation retains quota until worker exit', () async {
    final quota = DanmakuWorkQuota();
    final token = DanmakuWorkToken();
    late Future<void> successor;
    var successorStarted = false;
    final pending = quota.runWithLease(
      quota.maxBytes,
      (lease) => processOrderedDanmakuBatches(
        Stream.value([_dm('worker has processed this batch', 0)]),
        rules: DanmakuProcessingRules(),
        lease: lease,
        token: token,
        consume: (_) {
          expect(quota.snapshot['runningTasks'], 1);
          token.cancel();
          successor = quota.run(1, () {
            successorStarted = true;
          });
          expect(successorStarted, isFalse);
        },
      ),
    );
    await expectLater(pending, throwsA(isA<DanmakuWorkCancelled>()));
    await successor;
    expect(successorStarted, isTrue);
    expect(quota.snapshot['runningTasks'], 0);
  });
  test('oversized rule description fails before constructing its snapshot', () {
    expect(
      () => DanmakuProcessingRules(
        filter: RuleFilter(['x' * (1024 * 1024)], [], {}),
      ),
      throwsA(isA<DanmakuWorkTooLarge>()),
    );
  });
  test(
    'insufficient inherited lease and oversized first item are rejected',
    () async {
      final quota = DanmakuWorkQuota();
      await expectLater(
        quota.runWithLease(
          1024,
          (lease) => mergeDanmakuInBackground([_dm('small', 0)], lease: lease),
        ),
        throwsA(isA<DanmakuWorkTooLarge>()),
      );
      await expectLater(
        mergeDanmakuInBackground([
          _dm('x' * DanmakuProcessingBudget.batchBytes, 0),
        ]),
        throwsA(isA<DanmakuWorkTooLarge>()),
      );
      expect(DanmakuWorkQuota.instance.snapshot['runningTasks'], 0);
    },
  );
  test('worker snapshots filters, marks own messages and preserves disabled merge order', () async {
    final filter = RuleFilter(
      ['blocked'],
      [RegExp('pattern', caseSensitive: false)],
      {'uid'},
    );
    final rules = DanmakuProcessingRules(
      merge: false,
      selfHash: 'own',
      fileSource: false,
      segmentIndex: 0,
      filter: filter,
    );
    filter.dmFilterString.clear();
    filter.dmRegExp.clear();
    filter.dmUid.clear();
    final input = [
      _dm('late', 200),
      _dm('early', 100),
      _dm('blocked', 101),
      _dm('PATTERN', 102),
      DanmakuElement(
        content: 'uid only',
        progress: 103,
        mode: 1,
        midHash: 'uid',
      ),
      DanmakuElement(
        content: 'blocked own',
        progress: 104,
        mode: 1,
        midHash: 'own',
      ),
      _dm('blocked stale own', 105, self: true),
      _dm('other segment', 360000),
    ];
    final result = await processDanmakuInBackground(input, rules: rules);
    expect(result.map((e) => e.content), ['late', 'early', 'blocked own']);
    expect(result.last.isSelf, isTrue);
    expect(result.every((e) => e.count == 0), isTrue);
    expect(input[5].isSelf, isFalse);
    expect(input[6].isSelf, isTrue);
  });

  test('filtering spans batches before duplicate admission', () async {
    final input = [
      for (var i = 0; i < 600; i++) _dm(i.isEven ? 'blocked' : 'keep', i),
    ];
    final result = await processDanmakuInBackground(
      input,
      rules: DanmakuProcessingRules(filter: RuleFilter(['blocked'], [], {})),
    );
    expect(result.single.content, 'keep');
    expect(result.single.count, 300);
    expect(input.every((e) => e.count == 0), isTrue);
  });

  test(
    'worker output matches in-process merge for a dense mixed batch',
    () async {
      List<DanmakuElement> inputItems() => List.generate(
        1100,
        (i) => _dm(
          i % 4 == 0 ? '相同长弹幕内容' : '原始条目$i',
          i * 11,
          mode: i % 19 == 0 ? 7 : 1,
          self: i % 37 == 0,
        ),
      )..shuffle(Random(19));
      final input = inputItems();
      final expected = DanmakuMerger().merge(inputItems());
      final actual = await mergeDanmakuInBackground(input);
      Object snapshot(DanmakuElement element) => (
        element.progress,
        element.content,
        element.mode,
        element.isSelf,
        element.count,
      );
      expect(
        actual.map(snapshot),
        expected.map(snapshot),
      );
      expect(input.every((e) => e.count == 0), isTrue);
    },
  );

  test(
    'cancelled background work finishes before its quota is released',
    () async {
      final token = DanmakuWorkToken();
      final pending = mergeDanmakuInBackground(
        List.generate(600, (i) => _dm('重复', i)),
        token: token,
      );
      Timer.run(token.cancel);
      await expectLater(pending, throwsA(isA<DanmakuWorkCancelled>()));
      expect(DanmakuWorkQuota.instance.snapshot['runningTasks'], 0);
      expect(await DanmakuWorkQuota.instance.run(1, () => 42), 42);
    },
  );

  test(
    'background merge preserves metadata and leaves input untouched',
    () async {
      final elements = [
        DanmakuElement(
          content: '同样的内容',
          progress: 20,
          mode: 1,
          idStr: 'original',
        ),
        _dm('同样的内容', 30),
        _dm('同样的内容', 40, self: true),
        _dm('同样的内容', 10, mode: 5),
      ];
      final originalCounts = elements.map((e) => e.count).toList();
      var eventLoopRan = false;
      final timer = Timer(Duration.zero, () => eventLoopRan = true);
      final result = await mergeDanmakuInBackground(elements);
      // 后台完成前主 isolate 可以处理事件；结果携带完整弹幕元数据。
      expect(eventLoopRan, isTrue);
      timer.cancel();
      expect(result.map((e) => e.progress), [10, 20, 40]);
      expect(result.map((e) => e.count), [1, 2, 1]);
      expect(result[1].idStr, 'original');
      expect(result.last.isSelf, isTrue);
      expect(elements.map((e) => e.count), originalCounts);
    },
  );
}
