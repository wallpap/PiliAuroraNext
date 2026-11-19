class DanmakuTimelineEntry {
  const DanmakuTimelineEntry({
    required this.positionUs,
    required this.content,
    this.id = 0,
    this.idStr = '',
    this.mode = 0,
    this.fontSize = 0,
    this.color = 0,
    this.midHash = '',
    this.weight = 0,
    this.likeCount = 0,
    this.count = 0,
    this.isSelf = false,
    this.vipGradient = false,
  });

  final int positionUs;
  final String content;
  final int id;
  final String idStr;
  final int mode;
  final int fontSize;
  final int color;
  final String midHash;
  final int weight;
  final int likeCount;
  final int count;
  final bool isSelf;
  final bool vipGradient;

  static int comparePriority(
    DanmakuTimelineEntry first,
    DanmakuTimelineEntry second,
  ) => compareDanmakuRank(
    first.isSelf,
    first.weight,
    second.isSelf,
    second.weight,
  );
}

int compareDanmakuRank(
  bool firstSelf,
  int firstWeight,
  bool secondSelf,
  int secondWeight,
) {
  if (firstSelf != secondSelf) return firstSelf ? -1 : 1;
  return secondWeight.compareTo(firstWeight);
}

enum DanmakuCoverageState { loaded, missing, loading, invalidated, failed }

class DanmakuRangeCoverage {
  const DanmakuRangeCoverage(this.startUs, this.endUs, this.state);

  final int startUs;
  final int endUs;
  final DanmakuCoverageState state;
}

/// 半开范围 [startUs, endUs) 的来源快照；读取不改变缓存淘汰顺序。
class DanmakuTimelineRange {
  DanmakuTimelineRange({
    required this.startUs,
    required this.endUs,
    required this.revision,
    this.ruleRevision = 0,
    required Iterable<DanmakuTimelineEntry> entries,
    required Iterable<DanmakuRangeCoverage> coverage,
  }) : entries = List.unmodifiable(entries),
       coverage = List.unmodifiable(coverage);

  final int startUs;
  final int endUs;
  final int revision;
  final int ruleRevision;
  final List<DanmakuTimelineEntry> entries;
  final List<DanmakuRangeCoverage> coverage;

  bool get isLoaded => coverage.every(
    (range) => range.state == DanmakuCoverageState.loaded,
  );
}

enum DanmakuSourceChangeKind { invalidated, ready, coverage }

class DanmakuSourceChange {
  const DanmakuSourceChange({
    required this.kind,
    required this.ruleRevision,
    this.startUs = 0,
    this.endUs,
  });

  final DanmakuSourceChangeKind kind;
  final int ruleRevision;
  final int startUs;

  /// null 表示整个来源，包括已离开当前读取范围的内容。
  final int? endUs;
}

abstract interface class DanmakuTimelineSource {
  Stream<DanmakuSourceChange> get changes;

  /// 按媒体时间和来源次序读取；各 100 ms 桶的范围交集优先保留自己发送及高权重项，
  /// 覆盖状态仍描述完整请求范围。
  DanmakuTimelineRange readRange(
    int startUs,
    int endUs, {
    int? maxEntriesPerBucket,
  });
  Future<void> ensureRange(int startUs, int endUs);
}
