import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/episode.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/result.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';
import 'package:pili_aurora_next/pages/video/share_card/artwork.dart';
import 'package:pili_aurora_next/pages/video/share_card/content.dart';
import 'package:pili_aurora_next/pages/video/share_card/preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通视频卡片包含投稿信息，二维码使用稿件链接', () {
    final date = DateTime(2025, 2, 9, 12).millisecondsSinceEpoch ~/ 1000;
    final video = VideoDetailData.fromJson({
      'title': '「8K延时」重庆极致内透！1000天拍摄时长！',
      'owner': {'mid': 123, 'name': '测试作者'},
      'pubdate': date,
      'duration': 300,
      'stat': {'view': 26000, 'like': 859, 'danmaku': 65},
      'pages': [
        {'cid': 11, 'part': '上篇', 'duration': 72},
        {'cid': 22, 'part': '下篇', 'duration': 228},
      ],
    });
    final card = VideoShareCardContent.video(
      video,
      bvid: 'BV17x411w7KC',
      cid: 22,
      followers: 237000,
    );
    expect(card.url, 'https://www.bilibili.com/video/BV17x411w7KC/');
    expect(card.fileName, 'BV17x411w7KC-分享卡片');
    expect(card.title, video.title);
    expect(card.headline, '重庆极致内透！1000天拍摄时长！');
    expect(card.subtitle, '下篇');
    expect(card.duration, '03:48');
    expect(card.authorMetadata(card.followers), '23.7万 粉丝  ·  2025.02.09 发布');
    expect(card.metrics, '2.6万播放  ·  859点赞  ·  65弹幕');
  });

  for (final (type, kind, subtitle) in [
    (1, '番剧', '第2话  旅途'),
    (2, '电影', '正片'),
    (3, '纪录片', '第2集  旅途'),
    (5, '电视剧', '第2集  旅途'),
  ]) {
    test('$kind 卡片使用当前分集的链接、封面和上线信息', () {
      final date = DateTime(2023, 9, 29, 12).millisecondsSinceEpoch ~/ 1000;
      final card = VideoShareCardContent.episode(
        PgcInfoModel(type: type, title: '合成作品', cover: 'season.jpg'),
        epId: 456,
        episode: EpisodeItem(
          id: 456,
          title: '2',
          longTitle: '旅途',
          cover: 'episode.jpg',
          duration: 1425000,
          pubTime: date,
        ),
      );
      expect(card.url, 'https://www.bilibili.com/bangumi/play/ep456');
      expect(card.fileName, 'ep456-分享卡片');
      expect(card.kind, kind);
      expect(card.subtitle, subtitle);
      expect(card.cover, 'episode.jpg');
      expect(card.artwork, type == 2 ? 'season.jpg' : isNull);
      expect(card.publication, '2023.09.29 上线');
      expect(card.duration, '23:45');
    });
  }

  test('电影附加内容显示该条目的标题和链接', () {
    final movie = PgcInfoModel.fromJson({
      'type': 2,
      'title': '合成电影',
      'episodes': [
        {'id': 1, 'title': '正片'},
      ],
      'section': [
        {
          'title': '预告',
          'episodes': [
            {'id': 2, 'long_title': '最终预告'},
          ],
        },
      ],
    });
    final card = VideoShareCardContent.episode(
      movie,
      epId: 2,
      episode: movie.section!.single.episodes!.single,
    );
    expect(card.subtitle, '最终预告');
    expect(card.watchLabel, '扫码在哔哩哔哩观看本集');
    expect(card.url, 'https://www.bilibili.com/bangumi/play/ep2');
  });

  test('沉浸海报输出 920 × 1040 PNG', () async {
    final card = VideoShareCardContent.episode(
      PgcInfoModel(type: 2, title: '合成电影'),
      epId: 456,
    );
    final code = VideoShareCardPainter.qrImage(card.url);
    final bytes = await VideoShareCardPainter(content: card, code: code).png();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(16), 920);
    expect(header.getUint32(20), 1040);
  });

  for (final (name, size, bounds, withArtwork) in [
    ('宽屏', const Size(320, 180), const Rect.fromLTWH(0, 0, 460, 259), false),
    ('方形', const Size(200, 200), const Rect.fromLTWH(99, 0, 262, 262), false),
    ('竖版', const Size(200, 300), const Rect.fromLTWH(143, 0, 174, 262), false),
    (
      '电影横封与海报',
      const Size(320, 180),
      const Rect.fromLTWH(0, 0, 304, 171),
      true,
    ),
  ]) {
    test('$name 海报保留封面的四角并延展到边缘', () async {
      final card = VideoShareCardContent.episode(
        PgcInfoModel(type: withArtwork ? 2 : 1, title: '合成作品'),
        epId: 456,
      );
      final cover = await _markedCover(size);
      addTearDown(cover.dispose);
      final artwork = withArtwork
          ? await _markedCover(const Size(200, 300))
          : null;
      if (artwork != null) addTearDown(artwork.dispose);
      final png = await VideoShareCardPainter(
        content: card,
        code: VideoShareCardPainter.qrImage(card.url),
        cover: cover,
        artwork: artwork,
      ).png();

      final codec = await ui.instantiateImageCodec(png);
      addTearDown(codec.dispose);
      final image = (await codec.getNextFrame()).image;
      addTearDown(image.dispose);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      _expectCoverCorners(pixels, image.width, bounds.deflate(15));
      final left = _posterPixel(pixels, image.width, const Offset(2, 4));
      final right = _posterPixel(pixels, image.width, const Offset(458, 4));
      if (bounds.width == 460) {
        expect(left.r, greaterThan(.9));
        expect(right.g, greaterThan(.9));
      } else {
        expect(left.r, greaterThan(.25));
        expect(right.r, greaterThan(.25));
      }
      expect(
        _posterPixel(pixels, image.width, const Offset(458, 323)),
        const Color(0xff151d37),
      );
      if (withArtwork) {
        _expectCoverCorners(
          pixels,
          image.width,
          const Rect.fromLTWH(319, 21, 112, 172),
        );
      }
    });
  }

  test('标题前保留封面亮度，暗部平滑衔接到底色', () async {
    final card = VideoShareCardContent.episode(
      PgcInfoModel(type: 1, title: '合成作品'),
      epId: 456,
    );
    final cover = await _markedCover(const Size(320, 180));
    addTearDown(cover.dispose);
    final png = await VideoShareCardPainter(
      content: card,
      code: VideoShareCardPainter.qrImage(card.url),
      cover: cover,
    ).png();
    final codec = await ui.instantiateImageCodec(png);
    addTearDown(codec.dispose);
    final image = (await codec.getNextFrame()).image;
    addTearDown(image.dispose);
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;

    double redAt(double top) =>
        _posterPixel(pixels, image.width, Offset(400, top)).r;

    expect(redAt(136), closeTo(120 / 255, .01));
    expect(redAt(206), inInclusiveRange(.33, .39));
    expect(redAt(245), inInclusiveRange(.22, .27));
    expect(redAt(321), closeTo(21 / 255, .01));
    expect(
      _posterPixel(pixels, image.width, const Offset(29, 221)).r,
      closeTo(redAt(221), .02),
    );
  });

  testWidgets('居中弹出的海报模糊并降低原页面亮度，点击外侧或 Esc 关闭', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card = VideoShareCardContent.episode(
      PgcInfoModel(type: 1, title: '合成番剧'),
      epId: 456,
    );
    final viewportKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: viewportKey,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: ColoredBox(color: Colors.black)),
                    Expanded(child: ColoredBox(color: Colors.white)),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showVideoShareCard(context, card),
                      child: const Text('生成分享卡片'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final viewport = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(viewportKey),
    );
    Future<ByteData> capture() async {
      final image = await viewport.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      } finally {
        image.dispose();
      }
    }

    int brightness(ByteData pixels, int x) =>
        pixels.getUint8((64 * 320 + x) * 4);

    final page = (await tester.runAsync(capture))!;
    expect(brightness(page, 156), 0);
    expect(brightness(page, 240), 255);

    final open = find.text('生成分享卡片');
    final poster = find.bySemanticsLabel(RegExp('合成番剧.*扫码'));
    final paintedPoster = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is VideoShareCardPainter,
    );
    await tester.tap(open);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opening = (await tester.runAsync(capture))!;
    await tester.pumpAndSettle();
    expect(poster, findsOneWidget);
    expect(tester.getCenter(paintedPoster).dx, 160);
    expect(find.byTooltip('下一种版式'), findsNothing);
    final popup = (await tester.runAsync(capture))!;
    expect(brightness(popup, 80), 0);
    expect(brightness(popup, 240), inInclusiveRange(1, 127));
    expect(brightness(popup, 156), greaterThan(brightness(popup, 80)));
    expect(brightness(popup, 164), lessThan(brightness(popup, 240)));
    expect(
      brightness(opening, 240),
      inExclusiveRange(brightness(popup, 240), brightness(page, 240)),
    );

    await tester.tapAt(tester.getCenter(paintedPoster));
    await tester.pumpAndSettle();
    expect(poster, findsOneWidget);
    await tester.tapAt(const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(poster, findsNothing);

    tester.view.physicalSize = const Size(640, 240);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('保存图片').hitTestable(), findsOneWidget);
    expect(tester.getRect(paintedPoster).top, closeTo(8, 0.01));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(poster, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<ui.Image> _markedCover(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & size, Paint()..color = const Color(0xff786878));
  const marker = 20.0;
  for (final (left, top, color) in [
    (0.0, 0.0, const Color(0xffff0000)),
    (size.width - marker, 0.0, const Color(0xff00ff00)),
    (0.0, size.height - marker, const Color(0xff0000ff)),
    (size.width - marker, size.height - marker, const Color(0xffffff00)),
  ]) {
    canvas.drawRect(
      Rect.fromLTWH(left, top, marker, marker),
      Paint()..color = color,
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  } finally {
    picture.dispose();
  }
}

void _expectCoverCorners(ByteData pixels, int width, Rect bounds) {
  final top = _posterPixel(pixels, width, bounds.topCenter);
  final bottom = _posterPixel(pixels, width, bounds.bottomCenter);
  final red = _posterPixel(pixels, width, bounds.topLeft);
  final green = _posterPixel(pixels, width, bounds.topRight);
  final blue = _posterPixel(pixels, width, bounds.bottomLeft);
  final yellow = _posterPixel(pixels, width, bounds.bottomRight);
  expect(red.r - top.r, greaterThan(.03));
  expect(green.g - top.g, greaterThan(.03));
  expect(blue.b - bottom.b, greaterThan(.03));
  expect(yellow.r - bottom.r, greaterThan(.03));
  expect(yellow.g - bottom.g, greaterThan(.03));
}

Color _posterPixel(ByteData pixels, int width, Offset position) {
  final offset =
      ((position.dy * 2).round() * width + (position.dx * 2).round()) * 4;
  final rgba = pixels.getUint32(offset);
  return Color((rgba >> 8) | 0xff000000);
}
