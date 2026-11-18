import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/cropped_image.dart';
import 'package:pili_aurora_next/models/remote/video/video_shot/data.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/preview_image_cache.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/seek_preview_timeline.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/seek_preview.dart';

VideoShotData _timelineData() => VideoShotData(
  imgXLen: 2,
  imgYLen: 2,
  imgXSize: 20,
  imgYSize: 10,
  image: ['a', 'b'],
  index: [0, 10, 20, 30, 40, 50],
);

ui.Image _sprite() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(40, 20);
  picture.dispose();
  return image;
}

void main() {
  testWidgets('索引预热延后且与拖动共用请求，返回时直接发布最新目标', (tester) async {
    final indexes = <int?>[];
    final data = Completer<VideoShotData>();
    var requests = 0;
    Future<VideoShotData> load(CancelToken token) {
      requests++;
      return data.future;
    }

    final timeline = SeekPreviewTimeline(indexes.add)
      ..prewarm(load: load, isCurrent: () => true);
    await tester.pump(const Duration(milliseconds: 999));
    expect(requests, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, 1);
    timeline
      ..select(10, load: load, isCurrent: () => true)
      ..select(40, load: load, isCurrent: () => true);
    expect(indexes, isEmpty);
    data.complete(_timelineData());
    await tester.pump();
    expect(indexes, [3]);
    expect(requests, 1);
  });

  testWidgets('松手不显示迟到索引，切源取消请求且丢弃旧响应', (tester) async {
    final indexes = <int?>[];
    final timeline = SeekPreviewTimeline(indexes.add);
    final released = Completer<VideoShotData>();
    timeline
      ..select(40, load: (_) => released.future, isCurrent: () => true)
      ..hide();
    released.complete(_timelineData());
    await tester.pump();
    expect(indexes, [null]);
    expect(timeline.data, isNotNull);

    timeline.clear();
    final stale = Completer<VideoShotData>();
    late CancelToken oldToken;
    timeline
      ..select(
        30,
        load: (token) {
          oldToken = token;
          return stale.future;
        },
        isCurrent: () => true,
      )
      ..clear();
    expect(oldToken.isCancelled, isTrue);
    final current = _timelineData();
    timeline.select(20, load: (_) async => current, isCurrent: () => true);
    stale.complete(_timelineData());
    await tester.pump();
    expect(timeline.data, same(current));
    expect(indexes.last, 1);
  });

  testWidgets('跨图保留上一张的裁剪，新图使用最新目标及显示尺寸', (tester) async {
    final cache = PreviewImageCache();
    addTearDown(cache.clear);
    final pending = <String, Completer<ui.Image?>>{};
    final sizes = <int>[];
    Future<void> show(String url, int x, int y) => tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.5),
        child: Center(
          child: VideoShotImage(
            imageCache: cache,
            url: url,
            x: x,
            y: y,
            columns: 2,
            rows: 2,
            height: 81,
            loadImage: (url, height) {
              sizes.add(height);
              return (pending[url] = Completer<ui.Image?>()).future;
            },
          ),
        ),
      ),
    );
    CroppedImage current() => tester.widget(find.byType(CroppedImage));

    await show('first', 1, 0);
    pending['first']!.complete(_sprite());
    await tester.pump();
    await tester.pump();
    final previous = current().image;
    expect(current().srcRect, const Rect.fromLTWH(20, 0, 20, 10));

    await show('second', 0, 1);
    await show('second', 1, 1);
    expect(current().image, same(previous));
    expect(current().srcRect, const Rect.fromLTWH(20, 0, 20, 10));
    expect(sizes, [256, 256]);
    pending['second']!.complete(_sprite());
    await tester.pump();
    await tester.pump();
    expect(current().image, isNot(same(previous)));
    expect(current().srcRect, const Rect.fromLTWH(20, 10, 20, 10));
    expect(previous.debugDisposed, isTrue);
  });
}
