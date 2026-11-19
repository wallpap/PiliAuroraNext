import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:pili_aurora_next/features/playback/data/seek_preview_repository.dart';
import 'package:pili_aurora_next/features/playback/domain/seek_preview.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

typedef SeekPreviewLoader = Future<LoadingState<SeekPreviewAtlas>> Function(
  SeekPreviewSource, {
  CancelToken? cancelToken,
});

class SeekPreviewTimeline {
  SeekPreviewTimeline(
    this._onFrame, {
    SeekPreviewLoader? load,
  }) : _load = load ?? SeekPreviewRepository.fetch;

  final void Function(SeekPreviewFrame?) _onFrame;
  final SeekPreviewLoader _load;
  SeekPreviewAtlas? _data;
  int? _seconds;
  bool _triedDuringSeek = false;
  Timer? _warmup;
  CancelToken? _request;

  void prewarm(
    SeekPreviewSource source, {
    required bool Function() isCurrent,
    required bool Function() canStart,
  }) {
    _warmup?.cancel();
    if (_data != null || _request != null || _triedDuringSeek) return;
    _warmup = Timer(const Duration(seconds: 1), () {
      _warmup = null;
      if (isCurrent() && canStart()) unawaited(_fetch(source, isCurrent));
    });
  }

  void select(
    SeekPreviewSource source,
    int seconds, {
    required bool Function() isCurrent,
  }) {
    if (_seconds == seconds && _data != null) return;
    _seconds = seconds;
    if (_data case final data?) {
      _onFrame(data.frameAt(seconds));
    } else if (_request == null && !_triedDuringSeek) {
      _warmup?.cancel();
      _warmup = null;
      _triedDuringSeek = true;
      unawaited(_fetch(source, isCurrent));
    }
  }

  Future<void> _fetch(
    SeekPreviewSource source,
    bool Function() isCurrent,
  ) async {
    final request = _request = CancelToken();
    try {
      final data = (await _load(source, cancelToken: request)).dataOrNull;
      if (!identical(_request, request) || !isCurrent() || data == null) return;
      _data = data;
      if (_seconds case final seconds?) _onFrame(data.frameAt(seconds));
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  void hide() {
    _seconds = null;
    _onFrame(null);
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
