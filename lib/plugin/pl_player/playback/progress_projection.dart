import 'dart:async';

import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';

/// 加载交接期间保留展示位置，滤除原生卸载与 open 发出的临时零值。
class PlaybackProgressProjection {
  int? _readyLoadId;
  Duration _duration = Duration.zero;
  Completer<void>? _waitingForDuration;

  Duration get duration => _duration;

  void suspendPosition() => _readyLoadId = null;

  void confirmLoad(int loadId) => _readyLoadId = loadId;

  bool acceptsPosition(PlaybackSnapshot snapshot) =>
      _readyLoadId != null &&
      snapshot.loadId == _readyLoadId &&
      (snapshot.phase == PlaybackPhase.ready ||
          snapshot.phase == PlaybackPhase.ended);

  void updateDuration(Duration duration) {
    _duration = duration;
    final pending = _waitingForDuration;
    if (duration > Duration.zero && pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> seekWhenDurationKnown(Future<void> Function() seek) async {
    cancelPendingSeek();
    if (_duration <= Duration.zero) {
      final pending = _waitingForDuration = Completer<void>();
      await pending.future;
      if (!identical(_waitingForDuration, pending)) return;
      _waitingForDuration = null;
    }
    await seek();
  }

  void cancelPendingSeek() {
    final pending = _waitingForDuration;
    _waitingForDuration = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}
