import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/cropped_image.dart';
import 'package:pili_aurora_next/features/playback/application/seek_preview_timeline.dart';
import 'package:pili_aurora_next/features/playback/domain/seek_preview.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/preview_image_cache.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/seek_preview.dart';

const _source = (bvid: 'BV-test', cid: 1);

SeekPreviewAtlas _timelineData({List<String> images = const ['a', 'b']}) =>
    SeekPreviewAtlas(
      columns: 2,
      rows: 2,
      images: images,
      timestamps: const [0, 10, 20, 30, 40, 50],
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
    final frames = <SeekPreviewFrame?>[];
    final data = Completer<LoadingState<SeekPreviewAtlas>>();
    var ready = true;
    var requests = 0;
    Future<LoadingState<SeekPreviewAtlas>> load(
      SeekPreviewSource source, {
      CancelToken? cancelToken,
    }) {
      requests++;
      return data.future;
    }

    final timeline = SeekPreviewTimeline(frames.add, load: load)
      ..prewarm(_source, isCurrent: () => true, canStart: () => ready);
    await tester.pump(const Duration(milliseconds: 999));
    expect(requests, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, 1);
    ready = false;
    timeline
      ..select(_source, 10, isCurrent: () => true)
      ..select(_source, 40, isCurrent: () => true);
    expect(frames, isEmpty);
    data.complete(Success(_timelineData()));
    await tester.pump();
    final frame = frames.single!;
    expect((frame.url, frame.column, frame.row), ('a', 1, 1));
    expect(requests, 1);
  });

  testWidgets('松手不显示迟到索引，切源取消请求且丢弃旧响应', (tester) async {
    final frames = <SeekPreviewFrame?>[];
    var response = Completer<LoadingState<SeekPreviewAtlas>>();
    late CancelToken token;
    final timeline =
        SeekPreviewTimeline(
            frames.add,
            load: (source, {cancelToken}) {
              token = cancelToken!;
              return response.future;
            },
          )
          ..select(_source, 40, isCurrent: () => true)
          ..hide();
    response.complete(Success(_timelineData()));
    await tester.pump();
    expect(frames, [null]);
    timeline.select(_source, 20, isCurrent: () => true);
    expect(frames.last?.column, 1);

    timeline.clear();
    final stale = response = Completer<LoadingState<SeekPreviewAtlas>>();
    timeline
      ..select(_source, 30, isCurrent: () => true)
      ..clear();
    expect(token.isCancelled, isTrue);
    response = Completer<LoadingState<SeekPreviewAtlas>>();
    final next = (bvid: _source.bvid, cid: 2);
    timeline.select(next, 50, isCurrent: () => true);
    response.complete(Success(_timelineData(images: ['current'])));
    stale.complete(Success(_timelineData()));
    await tester.pump();
    final frame = frames.last!;
    expect((frame.url, frame.column, frame.row), ('current', 1, 1));
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
