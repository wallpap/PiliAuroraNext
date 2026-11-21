import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';

class _DecodeClock extends AutomatedTestWidgetsFlutterBinding {
  int _tick = 0;
  final _pending = <int>{};

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) {
    final id = ++_tick;
    _pending.add(id);
    scheduleMicrotask(() {
      if (_pending.remove(id)) callback(Duration(seconds: id));
    });
    return id;
  }

  @override
  void cancelFrameCallbackWithId(int id) => _pending.remove(id);
}

class _DiskCache implements BaseCacheManager {
  _DiskCache(this.file);
  final File file;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool? withProgress,
  }) async* {
    yield FileInfo(file, FileSource.Cache, DateTime(2100), url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Counter {
  int decodes = 0;

  Future<ui.Codec> decode(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async => _CountedCodec(
    await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    ),
    this,
  );
}

class _CountedCodec implements ui.Codec {
  _CountedCodec(this.delegate, this.counter);
  final ui.Codec delegate;
  final _Counter counter;

  @override
  int get frameCount => delegate.frameCount;
  @override
  int get repetitionCount => delegate.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    counter.decodes++;
    return delegate.getNextFrame();
  }

  @override
  void dispose() => delegate.dispose();
}

typedef _Sample = ({int micros, int nativeFrames});

Future<_Sample> _staticBatch(int requests) async {
  final cache = _DiskCache(File('assets/images/trending_banner.png').absolute);
  final counter = _Counter();
  final clock = Stopwatch()..start();
  final images = await Future.wait([
    for (var request = 0; request < requests; request++)
      loadNetworkImageFrame(
        'https://example.test/poster',
        cacheManager: cache,
        maxDecodePixels: 1 << 16,
        decode: counter.decode,
      ),
  ]);
  clock.stop();
  for (final image in images) {
    expect(image!.width * image.height, lessThanOrEqualTo(1 << 16));
    image.dispose();
  }
  return (micros: clock.elapsedMicroseconds, nativeFrames: counter.decodes);
}

Future<_Sample> _animation(String asset, int frames) async {
  final provider = LocalImageProvider(File(asset).absolute);
  final counter = _Counter();
  final done = Completer<void>();
  var delivered = 0;
  final clock = Stopwatch()..start();
  final stream = provider.loadImage(provider, counter.decode);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    info.dispose();
    if (++delivered == frames) {
      clock.stop();
      stream.removeListener(listener);
      done.complete();
    }
  }, onError: done.completeError);
  stream.addListener(listener);
  await done.future;
  return (micros: clock.elapsedMicroseconds, nativeFrames: counter.decodes);
}

Future<void> _measure(String name, Future<_Sample> Function() run) async {
  await run();
  await run();
  final samples = [for (var sample = 0; sample < 7; sample++) await run()]
    ..sort((first, second) => first.micros.compareTo(second.micros));
  final median = samples[samples.length ~/ 2];
  printOnFailure('$name $samples');
  stdout.writeln(
    '$name median_us=${median.micros} native_frames=${median.nativeFrames}',
  );
}

void main() {
  _DecodeClock();
  test('file-backed first frames and four complete animation loops', () async {
    await _measure('png_single', () => _staticBatch(1));
    await _measure('png_four_concurrent', () => _staticBatch(4));
    await _measure(
      'gif_four_loops',
      () => _animation('assets/images/live/live.gif', 96),
    );
    await _measure(
      'webp_four_loops',
      () => _animation('assets/images/loading.webp', 96),
    );
  });
}
