import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';
import 'package:pili_aurora_next/pages/danmaku/merge.dart';
import 'package:pili_aurora_next/pages/danmaku/priority.dart';

void main() {
  test('selection', () {
    final source = _source(2000 * 96, bucketSize: 96);
    final buckets = [
      for (var offset = 0; offset < source.length; offset += 96)
        source.sublist(offset, offset + 96),
    ];
    _measure('selection', () {
      var checksum = 0;
      for (var replay = 0; replay < 8; replay++) {
        for (final bucket in buckets) {
          for (final item in selectDanmakuPriority(
            bucket,
            danmakuCandidatesPerBucket,
            compareDanmakuPriority,
          )) {
            checksum = _mix(checksum, item.id);
          }
        }
      }
      return (checksum: checksum, retainedBytes: null);
    });
  });
  test('retention', () {
    final source = _source(48000, bucketSize: 28);
    _measure('retention', () {
      var checksum = 0;
      var retainedBytes = 0;
      for (final maxElements in [36000, 16000]) {
        final retention = DanmakuPriorityRetention(
          maxElements: maxElements,
          maxPerBucket: danmakuCandidatesPerBucket,
          maxBytes: 20 << 20,
        );
        for (var index = 0; index < source.length; index++) {
          retention.add(index, source[index]);
        }
        for (final bucket in retention.buckets.values) {
          for (final item in bucket) {
            checksum = _mix(checksum, item.id);
          }
        }
        retainedBytes += retention.estimatedBytes;
      }
      return (checksum: checksum, retainedBytes: retainedBytes);
    });
  });
  test('merge', () {
    final source = _source(18000, bucketSize: 80);
    _measureMerge('merge', source);
  });
  test('merge-close', () {
    final source = _source(18000, bucketSize: 80);
    final variants = [
      for (final item in source)
        DanmakuElement(
          id: item.id,
          progress: item.progress,
          weight: item.weight,
          mode: 1,
          isSelf: item.isSelf,
          content:
              '这段${item.content.substring(0, 3)}视频效果大家一起看'
              '${item.content.substring(item.content.length - 3)}画面很有意思',
        ),
    ];
    _measureMerge('merge-close', variants);
  });
}

void _measureMerge(String name, List<DanmakuElement> source) {
  _measure(name, () {
    var checksum = 0;
    final cursor = DanmakuMergeCursor();
    final merged = cursor.appendOrdered(source);
    for (final item in merged) {
      checksum = _mix(_mix(checksum, item.id), item.count);
    }
    return (
      checksum: checksum,
      retainedBytes: cursor.groupBytes + cursor.normalizedBytes,
    );
  });
}

List<DanmakuElement> _source(int count, {required int bucketSize}) {
  final random = Random(716);
  const alphabet = '这段内容挺有意思大家一起看弹幕效果今天视频画面颜色变化';
  return List.generate(count, (index) {
    final text = String.fromCharCodes(
      List.generate(
        16,
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
    return DanmakuElement(
      id: index,
      content: index % 9 == 0 ? '这段真的挺有意思' : text,
      progress: index ~/ bucketSize * 100 + index % bucketSize,
      weight: random.nextInt(12),
      mode: 1,
      isSelf: index % 967 == 0,
    );
  }, growable: false);
}

int _mix(int previous, int value) => (previous * 31 + value) & 0x7fffffff;

void _measure(
  String name,
  ({int checksum, int? retainedBytes}) Function() action,
) {
  final expected = action();
  for (var warmup = 0; warmup < 2; warmup++) {
    if (action() != expected) throw StateError('Inconsistent output: $name');
  }
  final samples = <int>[];
  final clock = Stopwatch();
  for (var run = 0; run < 9; run++) {
    clock
      ..reset()
      ..start();
    final result = action();
    clock.stop();
    samples.add(clock.elapsedMicroseconds);
    if (result != expected) throw StateError('Inconsistent output: $name');
  }
  samples.sort();
  debugPrintSynchronously(
    jsonEncode({
      'workload': name,
      'medianUs': samples[samples.length ~/ 2],
      'samplesUs': samples,
      'peakRssBytes': ProcessInfo.maxRss,
      'retainedBytes': expected.retainedBytes,
      'checksum': expected.checksum,
    }),
  );
}
