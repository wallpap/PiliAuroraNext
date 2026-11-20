import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/services/app_exit.dart';
import 'package:pili_aurora_next/services/logger.dart';

enum ShutdownAction { pause, exit }

final _scheduledExit = AppExit(
  cleanup: [
    (
      'progress',
      () async {
        if (PlPlayerController.instance case final player?) {
          await player.makeHeartBeat(
            player.position.value,
            type: .completed,
            isManual: true,
          );
        }
      },
    ),
  ],
  terminate: () => AppExit.application!.close(),
);

ShutdownTimerService? _applicationTimer;

ShutdownTimerService get shutdownTimerService =>
    _applicationTimer ??= ShutdownTimerService(
      exit: _scheduledExit.close,
      notify: SmartDialog.showToast,
    );

void closeApplicationShutdownTimer() {
  _applicationTimer?.dispose();
  _applicationTimer = null;
}

class ShutdownTimerService {
  ShutdownTimerService({required this._exit, required this._notify});

  final Future<void> Function() _exit;
  final void Function(String) _notify;
  ShutdownPlaybackBinding? _player;
  ShutdownPlaybackBinding? _independentAudio;
  ShutdownPlaybackBinding? _waitingFor;
  int _generation = 0;
  Timer? _timer;
  DateTime? _deadline;
  int _durationInMinutes = 0;
  bool _disposed = false;

  ShutdownAction action = .pause;
  bool waitUntilCompleted = false;
  DateTime? get deadline => _deadline;
  bool get isActive => _timer?.isActive ?? false;
  bool get isWaiting => _waitingFor != null;
  int get durationInMinutes => _durationInMinutes;

  ShutdownPlaybackBinding? get _currentPlayer => _independentAudio ?? _player;

  ShutdownPlaybackBinding bindPlayer({
    required Future<void> Function() pause,
    required bool Function() isPlaying,
    bool independentAudio = false,
    bool supportsCompletion = true,
  }) {
    final binding = ShutdownPlaybackBinding._(
      this,
      pause,
      isPlaying,
      supportsCompletion,
    );
    if (_disposed) return binding;
    if (independentAudio) {
      _independentAudio = binding;
    } else {
      _player = binding;
    }
    if (_waitingFor != null && !identical(_waitingFor, _currentPlayer)) reset();
    return binding;
  }

  void _release(ShutdownPlaybackBinding binding) {
    if (identical(_independentAudio, binding)) {
      _independentAudio = null;
      reset();
    }
    if (identical(_player, binding)) {
      _player = null;
      if (identical(_waitingFor, binding)) reset();
    }
  }

  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _deadline = null;
    _waitingFor = null;
    _durationInMinutes = 0;
  }

  void startShutdownTimer(int minutes) {
    if (_disposed) return;
    reset();
    if (minutes == 0) {
      _notify('取消定时关闭');
      return;
    }
    _durationInMinutes = minutes;
    _notify('设置 ${formatShutdownMinutes(minutes)} 后定时关闭');
    final delay = Duration(minutes: minutes);
    _deadline = DateTime.now().add(delay);
    _timer = Timer(delay, () => unawaited(_expire()));
  }

  void dispose() {
    _disposed = true;
    reset();
    _player = null;
    _independentAudio = null;
  }

  Future<void> _expire() async {
    _timer = null;
    _deadline = null;
    final player = _currentPlayer;
    final action = this.action;
    if (player != null && (action == .pause || waitUntilCompleted)) {
      final playing = player._isPlaying();
      if (playing && waitUntilCompleted && player._supportsCompletion) {
        _waitingFor = player;
        return;
      }
      if (playing && action == .pause) {
        _durationInMinutes = 0;
        final generation = _generation;
        bool mayNotify() =>
            generation == _generation && identical(player, _currentPlayer);
        try {
          await player._pause();
          if (mayNotify()) _notify('定时时间已到，已暂停');
        } catch (error, stack) {
          logger
              .scoped('playback')
              .w(
                '定时暂停失败',
                error: error.runtimeType,
                stackTrace: stack,
              );
          if (mayNotify()) _notify('定时暂停失败，请手动暂停');
        }
        return;
      }
    }
    _durationInMinutes = 0;
    if (action == .exit) _syncProgressAndExit();
  }

  bool _complete(ShutdownPlaybackBinding binding) {
    if (!identical(_waitingFor, binding) ||
        !identical(_currentPlayer, binding)) {
      return false;
    }
    _waitingFor = null;
    _durationInMinutes = 0;
    switch (action) {
      case .pause:
        _notify('定时时间已到，已暂停');
      case .exit:
        _syncProgressAndExit();
    }
    return true;
  }

  void _syncProgressAndExit() {
    unawaited(
      Future<void>.sync(_exit).catchError((Object error, StackTrace stack) {
        if (!_disposed) _notify('退出应用失败，请重试');
      }),
    );
  }
}

final class ShutdownPlaybackBinding {
  ShutdownPlaybackBinding._(
    this._service,
    this._pause,
    this._isPlaying,
    this._supportsCompletion,
  );

  final ShutdownTimerService _service;
  final Future<void> Function() _pause;
  final bool Function() _isPlaying;
  final bool _supportsCompletion;

  bool get isBound =>
      identical(_service._player, this) ||
      identical(_service._independentAudio, this);

  bool complete() => _service._complete(this);

  void dispose() => _service._release(this);
}

String formatShutdownMinutes(int minutes) {
  if (minutes == 60) return '60分钟';
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  if (hour > 0) return minute > 0 ? '$hour小时$minute分钟' : '$hour小时';
  return '$minute分钟';
}
