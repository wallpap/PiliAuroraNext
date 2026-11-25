import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TabBarView, TabController;
import 'package:pili_aurora_next/common/widgets/inactive_paint_cleanup.dart';
import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({
    super.key,
    required this.bytes,
    required this.cellKey,
    this.externalContent = false,
    this.showImagesOverride,
  });

  final Uint8List bytes;
  final GlobalKey cellKey;
  final bool externalContent;
  final bool? showImagesOverride;

  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  final controller = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final active =
        widget.showImagesOverride ?? TickerMode.valuesOf(context).enabled;
    final list = ListView.builder(
      controller: controller,
      itemCount: 12,
      itemBuilder: (_, index) => RepaintBoundary(
        key: index == 1 ? widget.cellKey : null,
        child: SizedBox(
          height: 100,
          child: active
              ? Image.memory(widget.bytes, fit: BoxFit.fill)
              : const SizedBox.expand(),
        ),
      ),
    );
    return widget.externalContent
        ? Stack(children: [list, const Texture(textureId: 1)])
        : list;
  }
}

List<ui.Picture> _pictures(ContainerLayer layer) {
  final result = <ui.Picture>[];
  void visit(Layer layer) {
    if (layer is PictureLayer) result.add(layer.picture!);
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(layer);
  return result;
}

Future<Uint8List> _redPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

ImageCache _isolateImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  final previousMaximumSize = cache.maximumSize;
  cache
    ..clear()
    ..clearLiveImages()
    ..maximumSize = 0;
  addTearDown(() {
    cache
      ..clear()
      ..clearLiveImages()
      ..maximumSize = previousMaximumSize;
  });
  return cache;
}

Future<void> _waitForImagePaint(WidgetTester tester) async {
  bool ready() {
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    return images.isNotEmpty && images.every((image) => image.image != null);
  }

  final timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 2)) {
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) {
      await tester.pumpAndSettle();
      if (ready()) return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail('The visible image fixture did not finish painting');
}

RenderRepaintBoundary _boundaryOf(GlobalKey key) =>
    key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

Future<Uint8List> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary = _boundaryOf(key);
  return (await tester.runAsync(
    () async => _pixels(await boundary.toImage(pixelRatio: 1)),
  ))!;
}

class _TrackedOffsetLayer extends OffsetLayer {
  ui.EngineLayer? get currentEngineLayer => engineLayer;
}

class _TrackedBoundary extends SingleChildRenderObjectWidget {
  const _TrackedBoundary({super.key, required super.child});

  @override
  _RenderTrackedBoundary createRenderObject(BuildContext context) =>
      _RenderTrackedBoundary();
}

class _RenderTrackedBoundary extends RenderRepaintBoundary {
  @override
  _TrackedOffsetLayer updateCompositedLayer({OffsetLayer? oldLayer}) =>
      oldLayer as _TrackedOffsetLayer? ?? _TrackedOffsetLayer();
}

class _VirtualizedPaintPage extends StatefulWidget {
  const _VirtualizedPaintPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<_VirtualizedPaintPage> createState() => _VirtualizedPaintPageState();
}

class _VirtualizedPaintPageState extends State<_VirtualizedPaintPage> {
  final controller = ScrollController();
  final liveCards = <_VirtualizedPaintCardState>{};

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: const ScrollBehavior().copyWith(scrollbars: false),
    child: CustomScrollView(
      controller: controller,
      slivers: [
        InactiveFeedSliver(
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 100,
            ),
            itemCount: 100,
            itemBuilder: (_, index) => _VirtualizedPaintCard(
              bytes: widget.bytes,
              live: liveCards,
            ),
          ),
        ),
      ],
    ),
  );
}

class _VirtualizedPaintCard extends StatefulWidget {
  const _VirtualizedPaintCard({required this.bytes, required this.live});

  final Uint8List bytes;
  final Set<_VirtualizedPaintCardState> live;

  @override
  State<_VirtualizedPaintCard> createState() => _VirtualizedPaintCardState();
}

class _VirtualizedPaintCardState extends State<_VirtualizedPaintCard> {
  @override
  void initState() {
    super.initState();
    widget.live.add(this);
  }

  @override
  void dispose() {
    widget.live.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode.valuesOf(context).enabled
      ? Image.memory(widget.bytes, fit: BoxFit.fill)
      : const SizedBox.expand();
}

void main() {
  testWidgets('Windows releases nested hidden paint', (
    tester,
  ) async {
    final cellKeys = List.generate(32, (_) => GlobalKey());
    final grid = Column(
      children: [
        for (final key in cellKeys)
          RepaintBoundary(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 16,
                height: 16,
                child: ColoredBox(color: ui.Color(0xffff0000)),
              ),
            ),
          ),
      ],
    );
    Widget scene(bool active) => Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        offstage: !active,
        child: TickerMode(
          enabled: active,
          child: InactivePaintCleanup(child: grid),
        ),
      ),
    );
    await tester.pumpWidget(scene(true));
    final pictures = cellKeys
        .expand((key) => _pictures(_boundaryOf(key).debugLayer!))
        .toList();
    expect(pictures, hasLength(cellKeys.length));

    await tester.pumpWidget(scene(false));
    await tester.pumpAndSettle();
    expect(pictures.every((picture) => picture.debugDisposed), isTrue);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final (releaseContents, externalContent, lateCleanup) in [
    (false, false, false),
    (true, false, false),
    (true, true, false),
    (true, false, true),
  ]) {
    final shouldRelease = releaseContents && !externalContent;
    testWidgets(
      lateCleanup
          ? 'initially inactive cleanup releases a reparented retained subtree'
          : externalContent
          ? 'cleanup leaves a subtree containing external textures intact'
          : releaseContents
          ? 'releasing layer contents preserves state, scroll and restored pixels'
          : 'hidden image handles dispose while detached Pictures retain pixels',
      (tester) async {
        final bytes = (await tester.runAsync(_redPng))!;
        final cache = _isolateImageCache();

        final previousCreate = ui.Image.onCreate;
        final previousDispose = ui.Image.onDispose;
        var openImageHandles = 0;
        ui.Image.onCreate = (image) {
          previousCreate?.call(image);
          openImageHandles++;
        };
        ui.Image.onDispose = (image) {
          previousDispose?.call(image);
          openImageHandles--;
        };
        addTearDown(() {
          ui.Image.onCreate = previousCreate;
          ui.Image.onDispose = previousDispose;
        });

        final pageKey = GlobalKey<_RetainedPageState>();
        final cellKey = GlobalKey();
        final rootKey = GlobalKey();
        Widget scene(bool active, {bool? visible}) {
          Widget page = _RetainedPage(
            key: pageKey,
            bytes: bytes,
            cellKey: cellKey,
            externalContent: externalContent,
          );
          if (releaseContents && (!lateCleanup || !active)) {
            page = InactivePaintCleanup(child: page);
          }
          return Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: rootKey,
              child: TickerMode(
                enabled: active,
                child: Offstage(offstage: !(visible ?? active), child: page),
              ),
            ),
          );
        }

        await tester.pumpWidget(scene(true));
        await _waitForImagePaint(tester);
        pageKey.currentState!.controller.jumpTo(50);
        await _waitForImagePaint(tester);
        expect(openImageHandles, greaterThan(0));

        final boundary = _boundaryOf(cellKey);
        final oldPictures = _pictures(boundary.debugLayer!);
        expect(oldPictures, isNotEmpty);
        final before = await _capture(tester, rootKey);

        // 模拟 PageView 已将页面移入保活桶，随后活动通知才卸载图像。
        // 若同一帧隐藏和卸载，flushPaint 会先重画深层边界，旧图可正常释放。
        await tester.pumpWidget(scene(true, visible: false));
        expect(boundary.debugLayer!.attached, isFalse);
        await tester.pumpWidget(scene(false));
        await tester.pump();
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);
        expect(cache.liveImageCount, 0);
        expect(cache.currentSizeBytes, 0);
        expect(openImageHandles, 0);
        expect(pageKey.currentState!.controller.offset, 50);

        if (shouldRelease) {
          expect(oldPictures.every((picture) => picture.debugDisposed), isTrue);
        } else {
          expect(
            oldPictures.every((picture) => !picture.debugDisposed),
            isTrue,
          );
          expect(boundary.debugLayer!.attached, isFalse);
          // 所有 Dart ui.Image 句柄已释放，旧 display list 仍可画出源图像。
          final retainedPixels = await tester.runAsync(
            () async => _pixels(await oldPictures.single.toImage(1, 1)),
          );
          expect(retainedPixels, orderedEquals([255, 0, 0, 255]));
        }

        await tester.pumpWidget(scene(true));
        await _waitForImagePaint(tester);
        expect(pageKey.currentState!.controller.offset, 50);
        expect(await _capture(tester, rootKey), orderedEquals(before));

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(oldPictures.every((picture) => picture.debugDisposed), isTrue);
        expect(openImageHandles, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
  for (final releaseContents in [false, true]) {
    testWidgets(
      'real TabActivity ${releaseContents ? 'on Windows releases' : 'on Android retains'} old image Pictures',
      (tester) async {
        final bytes = (await tester.runAsync(_redPng))!;
        final cache = _isolateImageCache();

        final controller = TabController(
          length: 3,
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);
        final pageKey = GlobalKey<_RetainedPageState>();
        final cellKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: TabBarView(
              controller: controller,
              children: [
                TabActivity(
                  controller: controller,
                  index: 0,
                  child: _RetainedPage(
                    key: pageKey,
                    bytes: bytes,
                    cellKey: cellKey,
                  ),
                ),
                const SizedBox(),
                const SizedBox(),
              ],
            ),
          ),
        );
        await _waitForImagePaint(tester);
        pageKey.currentState!.controller.jumpTo(50);
        await tester.pumpAndSettle();
        final boundary = _boundaryOf(cellKey);
        final oldPictures = _pictures(boundary.debugLayer!);
        expect(oldPictures, isNotEmpty);

        controller.animateTo(2);
        await tester.pumpAndSettle();
        await tester.pump();
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);
        expect(cache.liveImageCount, 0);
        expect(cache.currentSizeBytes, 0);
        expect(pageKey.currentState!.controller.offset, 50);
        expect(
          oldPictures.every((picture) => picture.debugDisposed),
          releaseContents,
        );

        controller.animateTo(0);
        await _waitForImagePaint(tester);
        expect(pageKey.currentState!.controller.offset, 50);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(oldPictures.every((picture) => picture.debugDisposed), isTrue);
      },
      variant: TargetPlatformVariant.only(
        releaseContents ? TargetPlatform.windows : TargetPlatform.android,
      ),
    );
  }

  testWidgets(
    'late detachment releases native paint without losing restored pixels',
    (tester) async {
      final bytes = (await tester.runAsync(_redPng))!;
      final cache = _isolateImageCache();
      final pageKey = GlobalKey<_RetainedPageState>();
      final outerKey = GlobalKey();
      final screenshotKey = GlobalKey();
      final cellKey = GlobalKey();
      Widget scene({required bool active, required bool visible}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: screenshotKey,
              child: Stack(
                children: [
                  Offstage(
                    offstage: !visible,
                    child: _TrackedBoundary(
                      key: outerKey,
                      child: TickerMode(
                        enabled: active,
                        child: InactivePaintCleanup(
                          child: _RetainedPage(
                            key: pageKey,
                            bytes: bytes,
                            cellKey: cellKey,
                            showImagesOverride: visible,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    width: 8,
                    height: 8,
                    child: ColoredBox(color: ui.Color(0xff0000ff)),
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(scene(active: true, visible: true));
      await _waitForImagePaint(tester);
      final before = await _capture(tester, screenshotKey);
      await tester.pumpWidget(scene(active: false, visible: true));
      await tester.pumpWidget(scene(active: true, visible: true));
      await _waitForImagePaint(tester);
      expect(await _capture(tester, screenshotKey), orderedEquals(before));

      await tester.pumpWidget(scene(active: false, visible: true));
      final layer = _boundaryOf(outerKey).debugLayer! as _TrackedOffsetLayer;
      expect(layer.attached, isTrue);
      final oldEngineLayer = layer.currentEngineLayer!;
      await tester.pumpWidget(scene(active: false, visible: false));
      await tester.pumpAndSettle();
      expect(cache.liveImageCount, 0);
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(oldEngineLayer.dispose, throwsAssertionError);

      await tester.pumpWidget(scene(active: true, visible: true));
      await _waitForImagePaint(tester);
      expect(await _capture(tester, screenshotKey), orderedEquals(before));
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'hidden viewport releases old paint even after cards are disposed',
    (tester) async {
      final bytes = (await tester.runAsync(_redPng))!;
      final cache = _isolateImageCache();
      final pageKey = GlobalKey<_VirtualizedPaintPageState>();
      final screenshotKey = GlobalKey();
      Widget scene({required bool active, required bool visible}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: screenshotKey,
              child: Offstage(
                offstage: !visible,
                child: TickerMode(
                  enabled: active,
                  child: InactivePaintCleanup(
                    child: _VirtualizedPaintPage(key: pageKey, bytes: bytes),
                  ),
                ),
              ),
            ),
          );

      await tester.pumpWidget(scene(active: true, visible: true));
      await _waitForImagePaint(tester);
      final page = pageKey.currentState!;
      page.controller.jumpTo(50);
      await _waitForImagePaint(tester);
      final viewport = tester.renderObject<RenderViewport>(
        find.byType(Viewport),
      );
      final oldPictures = _pictures(viewport.debugLayer!);
      expect(oldPictures, isNotEmpty);
      expect(page.liveCards.length, greaterThan(4));
      final before = await _capture(tester, screenshotKey);

      await tester.pumpWidget(scene(active: true, visible: false));
      await tester.pumpWidget(scene(active: false, visible: false));
      await tester.pumpAndSettle();
      expect(pageKey.currentState!.liveCards.length, lessThanOrEqualTo(4));
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(cache.liveImageCount, 0);
      expect(cache.currentSizeBytes, 0);
      expect(oldPictures.every((picture) => picture.debugDisposed), isTrue);

      await tester.pumpWidget(scene(active: true, visible: true));
      await _waitForImagePaint(tester);
      expect(pageKey.currentState!.controller.offset, 50);
      expect(await _capture(tester, screenshotKey), orderedEquals(before));
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
