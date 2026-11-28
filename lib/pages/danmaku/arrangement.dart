import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:pili_aurora_next/pages/danmaku/timeline_window.dart';

class DanmakuMeasuredCandidate<T> {
  const DanmakuMeasuredCandidate({
    required this.identity,
    required this.sourceUs,
    required this.width,
    required this.height,
    required this.type,
    required this.payload,
    this.estimatedBytes = 0,
    this.selfSend = false,
    this.weight = 0,
    this.renderable = true,
    this.specialDurationUs,
  });

  final Object identity;
  final int sourceUs;
  final double width;
  final double height;
  final DanmakuItemType type;
  final T payload;
  final int estimatedBytes;
  final bool selfSend;
  final int weight;
  final bool renderable;
  final int? specialDurationUs;
}

class DanmakuArrangement<T> {
  const DanmakuArrangement(
    this.candidate,
    this.trajectory,
    this.track,
    this.scrolling, {
    this.suspended = false,
  });
  final DanmakuMeasuredCandidate<T> candidate;
  final DanmakuTrajectory? trajectory;
  final int track;
  final bool scrolling;
  final bool suspended;
  bool get accepted => trajectory != null;
  double? xAt(int mediaUs) => trajectory?.xAt(mediaUs / 1000);
}

/// 普通点播的局部贪心编排，测量与绘制资源由两端显示适配持有。
class DanmakuWindowPlanner<T> {
  DanmakuWindowPlanner({
    required this.option,
    required this.width,
    required this.trackHeight,
    required this.trackCount,
    this.padding = 0,
    this.maxActive = DanmakuDisplayLimits.maxActive,
    DanmakuTimelineWindow<DanmakuArrangement<T>>? window,
  }) : window = window ?? DanmakuTimelineWindow(),
       _random = math.Random(0);

  DanmakuOption option;
  final double width;
  final double trackHeight;
  final int trackCount;
  final double padding;
  final int maxActive;
  final DanmakuTimelineWindow<DanmakuArrangement<T>> window;
  final math.Random _random;

  List<DanmakuWindowItem<DanmakuArrangement<T>>> reflowActive(
    List<DanmakuWindowItem<DanmakuArrangement<T>>> items,
  ) {
    final occupancy = _ArrangementOccupancy<T>(
      trackHeight,
      trackCount,
      padding,
    );
    final placed = <Object, DanmakuWindowItem<DanmakuArrangement<T>>>{};
    for (final item in [
      ...items.where((item) => item.payload.suspended),
      ...items.where((item) => !item.payload.suspended),
    ]) {
      final arrangement = item.payload;
      final candidate = arrangement.candidate;
      if (candidate.type == DanmakuItemType.special) {
        placed[item.identity] = item;
        continue;
      }
      final motion = arrangement.trajectory!;
      final track = _findTrack(
        candidate,
        motion,
        occupancy,
        scrolling: arrangement.scrolling,
        suspended: arrangement.suspended,
        preferredTrack: arrangement.track,
      );
      if (track < 0) continue;

      final updated = DanmakuWindowItem(
        identity: item.identity,
        sourceUs: item.sourceUs,
        startUs: item.startUs,
        endUs: item.endUs,
        estimatedBytes: item.estimatedBytes,
        payload: DanmakuArrangement(
          candidate,
          _atTrack(motion, track),
          track,
          arrangement.scrolling,
          suspended: arrangement.suspended,
        ),
      );
      placed[item.identity] = updated;
      occupancy.add(updated);
    }
    return [for (final item in items) ?placed[item.identity]];
  }

  bool prepare(
    List<DanmakuMeasuredCandidate<T>> candidates, {
    required int generation,
    required int preparedUntilUs,
    int? lookaheadUntilUs,
  }) {
    if (generation != window.generation) return false;
    if (preparedUntilUs < window.validUntilUs) {
      throw ArgumentError.value(preparedUntilUs);
    }
    if (lookaheadUntilUs != null && lookaheadUntilUs < preparedUntilUs) {
      throw ArgumentError.value(lookaheadUntilUs, 'lookaheadUntilUs');
    }
    if (candidates.isEmpty) {
      return window.extend(
        const [],
        generation: generation,
        preparedUntilUs: preparedUntilUs,
        lookaheadUntilUs: lookaheadUntilUs,
      );
    }
    final pending = <DanmakuMeasuredCandidate<T>>[];
    final identities = <Object>{};
    var bytes = window.estimatedBytes;
    int? previous;
    for (final candidate in candidates) {
      if (candidate.sourceUs < 0 ||
          candidate.sourceUs > (lookaheadUntilUs ?? preparedUntilUs) ||
          (previous != null && candidate.sourceUs < previous) ||
          !candidate.width.isFinite ||
          candidate.width < 0 ||
          !candidate.height.isFinite ||
          candidate.height <= 0 ||
          candidate.estimatedBytes < 0) {
        throw ArgumentError('候选必须按媒体时间有序，且测量与预算有效');
      }
      previous = candidate.sourceUs;
      if (window.hasIdentity(candidate.identity) ||
          !identities.add(candidate.identity)) {
        continue;
      }
      pending.add(candidate);
      bytes += candidate.estimatedBytes + 256;
    }
    if (window.length + pending.length > window.maxItems ||
        bytes > window.maxBytes) {
      return false;
    }
    final ranked = pending.indexed.toList()
      ..sort((a, b) {
        final self = (b.$2.selfSend ? 1 : 0).compareTo(a.$2.selfSend ? 1 : 0);
        if (self != 0) return self;
        final weight = b.$2.weight.compareTo(a.$2.weight);
        return weight != 0 ? weight : a.$1.compareTo(b.$1);
      });
    final occupancy = _ArrangementOccupancy<T>(
      trackHeight,
      trackCount,
      padding,
    );
    final earliestUs = pending.isEmpty
        ? preparedUntilUs
        : pending.first.sourceUs;
    for (final item in window.preparedItems) {
      if (item.endUs > earliestUs) occupancy.add(item);
    }
    final additions = <DanmakuWindowItem<DanmakuArrangement<T>>>[];
    for (final (_, candidate) in ranked) {
      final arranged = _arrange(candidate, occupancy);
      final item = DanmakuWindowItem(
        identity: candidate.identity,
        sourceUs: candidate.sourceUs,
        startUs: candidate.sourceUs,
        endUs: arranged.trajectory == null
            ? candidate.sourceUs + 1
            : (arranged.trajectory!.endMs * 1000).ceil(),
        estimatedBytes: candidate.estimatedBytes + 256,
        payload: arranged,
      );
      additions.add(item);
      occupancy.add(item);
    }
    return window.extend(
      additions,
      generation: generation,
      preparedUntilUs: preparedUntilUs,
      lookaheadUntilUs: lookaheadUntilUs,
    );
  }

  DanmakuArrangement<T> _arrange(
    DanmakuMeasuredCandidate<T> candidate,
    _ArrangementOccupancy<T> occupancy,
  ) {
    DanmakuArrangement<T> rejected() =>
        DanmakuArrangement(candidate, null, -1, false);
    if (!candidate.renderable ||
        width <= 0 ||
        option.hideWhat(candidate.type)) {
      return rejected();
    }
    if (candidate.type == DanmakuItemType.special) {
      final duration = candidate.specialDurationUs;
      if (duration == null || duration <= 0) return rejected();
      final start = candidate.sourceUs / 1000;
      final motion = DanmakuTrajectory(
        startMs: start,
        endMs: start + duration / 1000,
        startX: 0,
        y: 0,
        width: candidate.width,
        height: candidate.height,
        velocity: 0,
      );
      if (!_withinCapacity(motion, occupancy.accepted, special: true)) {
        return rejected();
      }
      return DanmakuArrangement(candidate, motion, -1, false);
    }
    if (trackHeight <= 0 ||
        trackCount <= 0 ||
        option.duration <= 0 ||
        option.staticDuration <= 0) {
      return rejected();
    }
    var scrolling = candidate.type == DanmakuItemType.scroll;
    DanmakuTrajectory trajectory(bool scroll) {
      final speed = scroll
          ? DanmakuGeometry.scrollVelocity(
              width,
              candidate.width,
              option.durationInMilliseconds,
              fixed: option.scrollFixedVelocity,
            )
          : 0.0;
      final start = candidate.sourceUs / 1000;
      return DanmakuTrajectory(
        startMs: start,
        endMs:
            start +
            (scroll
                ? (width + candidate.width) / speed
                : option.staticDurationInMilliseconds),
        startX: scroll ? width : (width - candidate.width) / 2,
        y: 0,
        width: candidate.width,
        height: candidate.height,
        velocity: speed,
      );
    }

    var motion = trajectory(scrolling);
    var track = _findTrack(candidate, motion, occupancy, scrolling: scrolling);
    if (!scrolling &&
        option.static2Scroll &&
        (track < 0 || candidate.width > width)) {
      if (option.hideScroll) return rejected();
      scrolling = true;
      motion = trajectory(true);
      track = _findTrack(candidate, motion, occupancy, scrolling: true);
    }
    if (track < 0) return rejected();
    motion = _atTrack(motion, track);
    if (!_withinCapacity(motion, occupancy.accepted, special: false)) {
      return rejected();
    }
    return DanmakuArrangement(candidate, motion, track, scrolling);
  }

  DanmakuTrajectory _atTrack(DanmakuTrajectory motion, int track) =>
      DanmakuTrajectory(
        startMs: motion.startMs,
        endMs: motion.endMs,
        startX: motion.startX,
        y: track * trackHeight,
        width: motion.width,
        height: motion.height,
        velocity: motion.velocity,
      );

  int _findTrack(
    DanmakuMeasuredCandidate<T> candidate,
    DanmakuTrajectory motion,
    _ArrangementOccupancy<T> occupancy, {
    required bool scrolling,
    bool suspended = false,
    int? preferredTrack,
  }) {
    if (trackCount <= 0 || trackHeight <= 0) return -1;
    final lastTrack =
        trackCount - DanmakuGeometry.trackSpan(motion.height, trackHeight);
    if (lastTrack < 0) return -1;

    bool fits(int track, {bool allowNormalOverlap = false}) {
      final placed = _atTrack(motion, track);
      for (final entry in occupancy.at(placed, track)) {
        final other = entry.payload;
        final existing = other.trajectory!;
        final crossesTracks =
            motion.height > trackHeight || existing.height > trackHeight;
        if (crossesTracks || suspended || other.suspended) {
          if ((crossesTracks || !allowNormalOverlap) &&
              placed.overlapsDuring(existing, padding: padding)) {
            return false;
          }
          continue;
        }
        if (allowNormalOverlap || track != other.track) continue;
        final late = placed.startMs < existing.startMs;
        final later = late ? existing : placed;
        final earlier = late ? placed : existing;
        if (scrolling && other.scrolling && later.startX != width) {
          if (later.overlapsDuring(earlier)) return false;
          continue;
        }
        if (DanmakuGeometry.blocks(
          later,
          earlier,
          trackHeight: trackHeight,
          viewWidth: width,
          candidateScrolling: late ? other.scrolling : scrolling,
          existingScrolling: late ? scrolling : other.scrolling,
          sameTrack: true,
        )) {
          return false;
        }
      }
      return true;
    }

    final preferred = preferredTrack?.clamp(0, lastTrack);
    if (preferred != null && fits(preferred)) return preferred;
    final fromBottom = !scrolling && candidate.type == DanmakuItemType.bottom;
    for (var index = 0; index <= lastTrack; index++) {
      final track = fromBottom ? lastTrack - index : index;
      if (track != preferred && fits(track)) return track;
    }
    if (scrolling && (candidate.selfSend || option.massiveMode)) {
      final track =
          preferred ?? (candidate.selfSend ? 0 : _random.nextInt(trackCount));
      if (track <= lastTrack && fits(track, allowNormalOverlap: true)) {
        return track;
      }
    }
    return -1;
  }

  bool _withinCapacity(
    DanmakuTrajectory motion,
    Iterable<DanmakuWindowItem<DanmakuArrangement<T>>> existing, {
    required bool special,
  }) {
    // 前瞻条目按共同存活区间计入总额度和独立的高级额度。
    var overlaps = 1;
    var specialOverlaps = special ? 1 : 0;
    var activeAtStart = 1;
    var specialAtStart = special ? 1 : 0;
    for (final item in existing) {
      final other = item.payload.trajectory;
      if (other == null) continue;
      final start = math.max(motion.startMs, other.startMs);
      final end = math.min(motion.endMs, other.endMs);
      final advanced = item.payload.candidate.type == DanmakuItemType.special
          ? 1
          : 0;
      if (start < end) {
        overlaps++;
        specialOverlaps += advanced;
        if (other.startMs <= motion.startMs) {
          activeAtStart++;
          specialAtStart += advanced;
        }
      }
    }
    if (activeAtStart > maxActive ||
        specialAtStart > DanmakuDisplayLimits.maxActiveSpecial) {
      return false;
    }
    if (overlaps <= maxActive &&
        specialOverlaps <= DanmakuDisplayLimits.maxActiveSpecial) {
      return true;
    }
    // 常见的未满额路径不分配事件；仅区间交错且可能超额时计算精确峰值。
    final events = <(double, int, int)>[];
    for (final item in existing) {
      final other = item.payload.trajectory!;
      final start = math.max(motion.startMs, other.startMs);
      final end = math.min(motion.endMs, other.endMs);
      if (start >= end) continue;
      final advanced = item.payload.candidate.type == DanmakuItemType.special
          ? 1
          : 0;
      events
        ..add((start, 1, advanced))
        ..add((end, -1, -advanced));
    }
    events.sort((a, b) {
      final time = a.$1.compareTo(b.$1);
      return time == 0 ? a.$2.compareTo(b.$2) : time;
    });
    var active = 1;
    var advanced = special ? 1 : 0;
    if (active > maxActive) return false;
    for (final event in events) {
      active += event.$2;
      advanced += event.$3;
      if (active > maxActive ||
          advanced > DanmakuDisplayLimits.maxActiveSpecial) {
        return false;
      }
    }
    return true;
  }
}

/// 每批建立活动轨迹的纵向索引；拒绝项与高级项不参与普通轨道扫描。
class _ArrangementOccupancy<T> {
  _ArrangementOccupancy(this.trackHeight, this.trackCount, this.padding);
  final double trackHeight;
  final int trackCount;
  final double padding;
  final accepted = <DanmakuWindowItem<DanmakuArrangement<T>>>[];
  final _tracks = <int, List<DanmakuWindowItem<DanmakuArrangement<T>>>>{};

  void add(DanmakuWindowItem<DanmakuArrangement<T>> item) {
    final motion = item.payload.trajectory;
    if (motion == null) return;
    accepted.add(item);
    if (item.payload.candidate.type == DanmakuItemType.special ||
        trackHeight <= 0) {
      return;
    }
    final first = math.max(0, ((motion.y - 2 * padding) / trackHeight).floor());
    final last = math.min(
      trackCount - 1,
      ((motion.y + motion.height + 2 * padding) / trackHeight).floor(),
    );
    for (var i = first; i <= last; i++) {
      (_tracks[i] ??= []).add(item);
    }
  }

  Iterable<DanmakuWindowItem<DanmakuArrangement<T>>> at(
    DanmakuTrajectory motion,
    int track,
  ) {
    final span = DanmakuGeometry.trackSpan(motion.height, trackHeight);
    if (span == 1) return _tracks[track] ?? const [];
    return {
      for (var i = track; i < track + span; i++) ...?_tracks[i],
    };
  }
}
