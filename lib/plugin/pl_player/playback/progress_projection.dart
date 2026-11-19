import 'dart:async';

import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';

/// 加载交接期间保留展示位置，滤除原生卸载与 open 发出的临时零值。
class PlaybackProgressProjection {
  Duration? _initialPosition;
  int? _readyLoadId;
  Duration _duration = Duration.zero;
  Completer<void>? _waitingForDuration;

  bool get awaitingPosition => _initialPosition != null;
  Duration get duration => _duration;

  void begin(Duration position) => _initialPosition = position;

  void alignReadyLoad(int loadId, Duration? acceptedPosition) {
    if (loadId == _readyLoadId) return;
    _readyLoadId = loadId;
    if (awaitingPosition && acceptedPosition != null) begin(acceptedPosition);
  }

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

  bool accept(PlaybackPhase phase, Duration position) {
    if (phase != PlaybackPhase.ready && phase != PlaybackPhase.ended) {
      return false;
    }
    if (_initialPosition != null &&
        _initialPosition! > Duration.zero &&
        (position - _initialPosition!).abs() > const Duration(seconds: 2)) {
      return false;
    }
    _initialPosition = null;
    return true;
  }
}
