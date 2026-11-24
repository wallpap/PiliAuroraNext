import 'dart:collection';

import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';
import 'package:pili_aurora_next/pages/danmaku/timeline_range.dart';

/// 100 ms 的优先候选额度；真实素材与密集合成素材共同验证的折中值。
const danmakuCandidatesPerBucket = 12;

/// 负数表示先显示；自己发送的弹幕先于服务端权重，同权重保持来源次序。
int compareDanmakuPriority(DanmakuElement first, DanmakuElement second) =>
    compareDanmakuRank(
      first.isSelf,
      first.weight,
      second.isSelf,
      second.weight,
    );

/// 有界 top-k；返回来源次序，调用方继续遵守媒体时间顺序。
List<T> selectDanmakuPriority<T>(
  List<T> items,
  int limit,
  int Function(T, T) compare, {
  int start = 0,
  int? end,
}) {
  if (limit < 0) throw ArgumentError.value(limit, 'limit');
  final stop = RangeError.checkValidRange(start, end, items.length);
  if (limit == 0) return [];
  if (stop - start <= limit) {
    return start == 0 && stop == items.length
        ? items
        : items.sublist(start, stop);
  }
  final indices = List.generate(
    limit,
    (index) => start + index,
    growable: false,
  );
  bool ranksAfter(int left, int right) {
    final order = compare(items[left], items[right]);
    return order > 0 || (order == 0 && left > right);
  }

  void siftDown(int position, int index) {
    while (position < limit ~/ 2) {
      var child = position * 2 + 1;
      if (child + 1 < limit && ranksAfter(indices[child + 1], indices[child])) {
        child++;
      }
      final childIndex = indices[child];
      if (!ranksAfter(childIndex, index)) break;
      indices[position] = childIndex;
      position = child;
    }
    indices[position] = index;
  }

  for (var parent = limit ~/ 2 - 1; parent >= 0; parent--) {
    siftDown(parent, indices[parent]);
  }
  for (var index = start + limit; index < stop; index++) {
    if (compare(items[index], items[indices.first]) < 0) siftDown(0, index);
  }
  indices.sort();
  return [for (final index in indices) items[index]];
}

class _RetainedElement {
  _RetainedElement(this.index, this.element)
    : bytes = element.storageBytes + 64;
  final int index;
  final DanmakuElement element;
  final int bytes;
  int get bucket => element.progress ~/ 100;
}

/// 文件和网络来源共用数量、字节与分桶额度；满额后替换低权重项。
/// 双有序索引使单项替换为 O(log n)，索引容量不随来源大小增长。
class DanmakuPriorityRetention {
  DanmakuPriorityRetention({
    required this.maxElements,
    required this.maxPerBucket,
    required this.maxBytes,
    this.baseBytes = 0,
  }) : assert(maxElements > 0 && maxPerBucket > 0 && maxBytes > 0),
       assert(baseBytes >= 0),
       estimatedBytes = baseBytes;

  final int maxElements;
  final int maxPerBucket;
  final int maxBytes;
  final int baseBytes;
  int estimatedBytes;
  final _byIndex = <int, _RetainedElement>{};
  final _buckets = <int, SplayTreeSet<_RetainedElement>>{};
  final _all = SplayTreeSet<_RetainedElement>(_compare);
  bool get isEmpty => _all.isEmpty;

  static int _compare(_RetainedElement a, _RetainedElement b) {
    final priority = compareDanmakuPriority(b.element, a.element);
    return priority != 0 ? priority : b.index.compareTo(a.index);
  }

  void add(int index, DanmakuElement element) {
    final entry = _RetainedElement(index, element);
    final bucket = _buckets[entry.bucket];
    _RetainedElement? bucketVictim;
    var bytes = estimatedBytes + entry.bytes + (bucket == null ? 128 : 0);
    if (bucket != null && bucket.length >= maxPerBucket) {
      final worst = bucket.first;
      if (_compare(entry, worst) <= 0) return;
      bucketVictim = worst;
      bytes -= worst.bytes;
    }
    var retained = _all.length - (bucketVictim == null ? 0 : 1);
    List<_RetainedElement>? globalVictims;
    if (retained >= maxElements || bytes > maxBytes) {
      for (final worst in _all) {
        if (identical(worst, bucketVictim)) continue;
        if (_compare(entry, worst) <= 0) return;
        (globalVictims ??= []).add(worst);
        retained--;
        bytes -= worst.bytes;
        // 空桶回收的索引字节在提交时核算；预检保守计费。
        if (retained < maxElements && bytes <= maxBytes) break;
      }
    }
    if (retained >= maxElements || bytes > maxBytes) return;
    if (bucketVictim != null) _remove(bucketVictim);
    if (globalVictims != null) {
      for (final victim in globalVictims) {
        _remove(victim);
      }
    }
    _buckets
        .putIfAbsent(entry.bucket, () {
          estimatedBytes += 128;
          return SplayTreeSet(_compare);
        })
        .add(entry);
    _all.add(entry);
    _byIndex[index] = entry;
    estimatedBytes += entry.bytes;
  }

  void promote(int index, DanmakuElement element) {
    final previous = _byIndex[index];
    if (previous != null) _remove(previous);
    add(index, element);
  }

  void updateCount(int index, int count) =>
      _byIndex[index]?.element.count = count;

  void _remove(_RetainedElement entry) {
    _all.remove(entry);
    _byIndex.remove(entry.index);
    final bucket = _buckets[entry.bucket]!..remove(entry);
    estimatedBytes -= entry.bytes;
    if (bucket.isEmpty) {
      _buckets.remove(entry.bucket);
      estimatedBytes -= 128;
    }
  }

  Map<int, List<DanmakuElement>> get buckets => {
    for (final entry in _buckets.entries)
      entry.key: [
        for (final item
            in (entry.value.toList()
              ..sort((a, b) => a.index.compareTo(b.index))))
          item.element,
      ],
  };
}
