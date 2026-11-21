import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/image/src/animation_frames.dart';

ui.Image _image(int size) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size, size);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only complete sequences replay and each frame keeps its duration and ownership', () {
    final cache = AnimationFrameCache();
    final source = _image(8);
    final handles = source.debugGetOpenHandleStackTraces()!.length;
    final sequence = cache.reserve(2, source)!;
    final durations = [
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 215),
    ];
    sequence.remember(TimedImageFrame(source, durations.first));
    expect(sequence.next(), isNull);
    sequence.remember(TimedImageFrame(source, durations.last));
    final replayed = [for (var index = 0; index < 4; index++) sequence.next()!];
    cache.dispose();
    expect(sequence.next(), isNull);
    expect(cache.reserve(2, source), isNull);
    expect(replayed.map((frame) => frame.duration), [
      ...durations,
      ...durations,
    ]);
    for (final frame in replayed) {
      expect(frame.image.isCloneOf(source), isTrue);
      frame.image.dispose();
    }
    expect(source.debugGetOpenHandleStackTraces(), hasLength(handles));
    source.dispose();
  });

  test('active sequences share a byte limit and abandon a growing frame', () {
    final tiny = _image(8), larger = _image(256);
    final cache = AnimationFrameCache(maximumBytes: 4 * 4096);
    final first = cache.reserve(3, tiny)!
      ..remember(TimedImageFrame(tiny, Duration.zero));
    expect(cache.reserve(2, tiny), isNull);
    first.remember(TimedImageFrame(larger, Duration.zero));
    expect(first.next(), isNull);
    expect(tiny.debugGetOpenHandleStackTraces(), hasLength(1));
    final next = cache.reserve(4, tiny)!;
    first.dispose();
    expect(cache.reserve(2, tiny), isNull);
    next.dispose();
    expect(cache.reserve(4, tiny), isNotNull);
    cache.dispose();
    final standard = AnimationFrameCache();
    expect(standard.reserve(65, tiny), isNull);
    expect(standard.reserve(32, larger), isNull);
    standard.dispose();
    tiny.dispose();
    larger.dispose();
  });
}
