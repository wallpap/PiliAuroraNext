import 'dart:math' as math;
import 'dart:ui' as ui;

class AnimationFrameCache {
  AnimationFrameCache({this.maximumBytes = 16 << 20})
    : assert(maximumBytes >= 0);

  final int maximumBytes;
  static const _maximumSequenceBytes = 4 << 20;
  static const _maximumFrames = 64;
  final _sequences = <AnimationFrameSequence>{};
  int _reservedBytes = 0;
  bool _closed = false;

  AnimationFrameSequence? reserve(int frameCount, ui.Image first) {
    if (_closed || frameCount < 2 || frameCount > _maximumFrames) return null;
    final frameBytes = _frameBytes(first);
    final bytes = frameBytes * frameCount;
    if (bytes > _maximumSequenceBytes ||
        bytes > maximumBytes - _reservedBytes) {
      return null;
    }
    final sequence = AnimationFrameSequence._(this, frameCount, frameBytes);
    _reservedBytes += bytes;
    _sequences.add(sequence);
    return sequence;
  }

  static int _frameBytes(ui.Image image) => math.max(
    4096,
    image.width *
        image.height *
        (image.colorSpace == ui.ColorSpace.sRGB ? 4 : 16),
  );

  void dispose() {
    _closed = true;
    for (final sequence in _sequences.toList()) {
      sequence.dispose();
    }
  }
}

class AnimationFrameSequence {
  AnimationFrameSequence._(this._cache, this._length, this._frameBytes);

  final AnimationFrameCache _cache;
  final int _length;
  final int _frameBytes;
  final _frames = <TimedImageFrame>[];
  int _next = 0;
  bool _disposed = false;

  void remember(ui.FrameInfo frame) {
    if (_disposed || _frames.length == _length) return;
    if (AnimationFrameCache._frameBytes(frame.image) > _frameBytes) {
      dispose();
      return;
    }
    _frames.add(TimedImageFrame(frame.image.clone(), frame.duration));
  }

  ui.FrameInfo? next() {
    if (_frames.length != _length) return null;
    final frame = _frames[_next];
    _next = (_next + 1) % _length;
    return TimedImageFrame(frame.image.clone(), frame.duration);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final frame in _frames) {
      frame.image.dispose();
    }
    _frames.clear();
    _cache._sequences.remove(this);
    _cache._reservedBytes -= _length * _frameBytes;
  }
}

class TimedImageFrame implements ui.FrameInfo {
  TimedImageFrame(this.image, this.duration);

  @override
  final ui.Image image;
  @override
  final Duration duration;
}
