import 'dart:async';
import 'dart:math' show max;

import 'package:dio/dio.dart' show CancelToken;
import 'package:pili_aurora_next/models/remote/video/video_shot/data.dart';

class SeekPreviewTimeline {
  SeekPreviewTimeline(this._onIndex);

  final void Function(int?) _onIndex;
  VideoShotData? _data;
  VideoShotData? get data => _data;
  int? _seconds;
  bool _triedDuringSeek = false;
  Timer? _warmup;
  CancelToken? _request;

  void prewarm({
    required Future<VideoShotData?> Function(CancelToken) load,
    required bool Function() isCurrent,
  }) {
    _warmup?.cancel();
    if (_data != null || _request != null || _triedDuringSeek) return;
    _warmup = Timer(const Duration(seconds: 1), () {
      _warmup = null;
      if (isCurrent()) unawaited(_fetch(load, isCurrent));
    });
  }

  void select(
    int seconds, {
    required Future<VideoShotData?> Function(CancelToken) load,
    required bool Function() isCurrent,
  }) {
    _seconds = seconds;
    if (_data case final data?) {
      _publish(data, seconds);
    } else if (_request == null && !_triedDuringSeek) {
      _warmup?.cancel();
      _warmup = null;
      _triedDuringSeek = true;
      unawaited(_fetch(load, isCurrent));
    }
  }

  Future<void> _fetch(
    Future<VideoShotData?> Function(CancelToken) load,
    bool Function() isCurrent,
  ) async {
    final request = _request = CancelToken();
    try {
      final data = await load(request);
      if (!identical(_request, request) || !isCurrent() || data == null) return;
      _data = data;
      if (_seconds case final seconds?) _publish(data, seconds);
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  void _publish(VideoShotData data, int seconds) {
    var low = 0;
    var high = data.index.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (data.index[middle] <= seconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _onIndex(max(0, low - 2));
  }

  void hide() {
    _seconds = null;
    _onIndex(null);
  }

  void clear() {
    _warmup?.cancel();
    _warmup = null;
    _request?.cancel();
    _request = null;
    _data = null;
    _triedDuringSeek = false;
    hide();
  }
}
