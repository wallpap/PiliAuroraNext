import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TabBarView, TabController;
import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';

class _Card extends StatefulWidget {
  const _Card({
    required this.index,
    required this.height,
    required this.live,
    required this.keepAlive,
  });

  final int index;
  final double height;
  final Set<_CardState> live;
  final bool keepAlive;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

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
  Widget build(BuildContext context) {
    super.build(context);
    return Semantics(
      label: 'card ${widget.index}',
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: ui.Color(0xff000000 | ((widget.index * 0x234567) & 0xffffff)),
          child: Text(
            'card ${widget.index}\ntitle ${widget.index}\nauthor\nviews',
            style: const TextStyle(fontSize: 12, color: ui.Color(0xffffffff)),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatefulWidget {
  const _Page({
    super.key,
    required this.grid,
    this.itemKeepAlive = false,
    this.headerExtent = 0,
  });

  final bool grid;
  final bool itemKeepAlive;
  final double headerExtent;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with AutomaticKeepAliveClientMixin {
  final controller = ScrollController();
  final loadedData = List.generate(500, (index) => index);
  final live = <_CardState>{};
  final budgetKey = GlobalKey();

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
    Widget buildCard(BuildContext _, int index) => _Card(
      index: loadedData[index],
      height: widget.grid ? 100 : (index.isEven ? 40 : 400),
      live: live,
      keepAlive: widget.itemKeepAlive,
    );
    final body = InactiveFeedSliver(
      key: budgetKey,
      sliver: widget.grid
          ? SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 100,
              ),
              itemCount: loadedData.length,
              itemBuilder: buildCard,
            )
          : SliverList.builder(
              itemCount: loadedData.length,
              itemBuilder: buildCard,
            ),
    );
    return CustomScrollView(
      controller: controller,
      scrollCacheExtent: const ScrollCacheExtent.pixels(250),
      slivers: [
        if (widget.headerExtent == 0)
          body
        else
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: widget.headerExtent,
                  child: const ColoredBox(color: ui.Color(0xff123456)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                sliver: body,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
            ],
          ),
      ],
    );
  }
}

Future<Uint8List> _capture(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _CorrectionSliver extends LeafRenderObjectWidget {
  const _CorrectionSliver({super.key});

  @override
  _RenderCorrectionSliver createRenderObject(BuildContext context) =>
      _RenderCorrectionSliver();
}

class _RenderCorrectionSliver extends RenderSliver {
  bool correctOnce = false;

  @override
  void performLayout() {
    if (correctOnce) {
      correctOnce = false;
      geometry = const SliverGeometry(scrollOffsetCorrection: 10);
    } else {
      geometry = SliverGeometry(
        scrollExtent: 1000,
        maxPaintExtent: 1000,
        paintExtent: constraints.remainingPaintExtent,
      );
    }
  }
}

void main() {
  testWidgets(
    'inactive extent preservation forwards real scroll offset corrections',
    (tester) async {
      final active = ValueNotifier(true);
      final controller = ScrollController();
      final correctionKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, enabled, _) => TickerMode(
              enabled: enabled,
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  InactiveFeedSliver(
                    sliver: _CorrectionSliver(key: correctionKey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(100);
      await tester.pumpAndSettle();
      (correctionKey.currentContext!.findRenderObject()!
                  as _RenderCorrectionSliver)
              .correctOnce =
          true;
      active.value = false;
      await tester.pumpAndSettle();
      expect(controller.offset, 110);
      active.value = true;
      await tester.pumpAndSettle();
      expect(controller.offset, 110);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      active.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final (grid, offset, keepAlive, headerExtent) in [
    (true, 0.0, false, 0.0),
    (true, 300.0, false, 0.0),
    (true, 335.0, false, 0.0),
    (false, 500.0, false, 0.0),
    (false, 109125.0, false, 0.0),
    (false, 500.0, true, 0.0),
    (true, 500.0, false, 100.0),
    (true, 12200.0, false, 100.0),
    (false, 109245.0, false, 100.0),
    (true, 0.0, false, 1000.0),
    (false, 0.0, false, 1000.0),
  ]) {
    testWidgets(
      '${grid ? 'grid' : 'variable list'} offset=$offset keepAlive=$keepAlive header=$headerExtent',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final tabs = TabController(
            length: 3,
            vsync: tester,
            animationDuration: const Duration(milliseconds: 100),
          );
          addTearDown(tabs.dispose);
          final pageKey = GlobalKey<_PageState>();
          final screenshotKey = GlobalKey();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: screenshotKey,
                child: ScrollConfiguration(
                  // 滚动条的延时淡出不属于列表内容，避免比较两个不同动画阶段。
                  behavior: const ScrollBehavior().copyWith(scrollbars: false),
                  child: TabBarView(
                    controller: tabs,
                    children: [
                      TabActivity(
                        controller: tabs,
                        index: 0,
                        child: _Page(
                          key: pageKey,
                          grid: grid,
                          itemKeepAlive: keepAlive,
                          headerExtent: headerExtent,
                        ),
                      ),
                      const SizedBox(),
                      const SizedBox(),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final page = pageKey.currentState!;
          page.controller.jumpTo(offset);
          await tester.pumpAndSettle();
          final initialOffset = page.controller.offset;
          final initialMax = page.controller.position.maxScrollExtent;
          final activeCards = page.live.length;
          final boundary =
              screenshotKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final before = await tester.runAsync(() => _capture(boundary));
          RenderSliver sliverOf(_PageState page) =>
              page.budgetKey.currentContext!.findRenderObject()!
                  as RenderSliver;
          final outsideCache =
              sliverOf(page).constraints.remainingCacheExtent == 0;
          if (!outsideCache) expect(activeCards, greaterThan(grid ? 4 : 1));

          tabs.animateTo(2);
          await tester.pumpAndSettle();
          final hiddenPage = pageKey.currentState!;
          final hiddenCards = hiddenPage.live.length;
          final hiddenPosition = hiddenPage.controller.position;
          final budget = sliverOf(hiddenPage);
          expect(
            budget.geometry!.cacheExtent,
            lessThanOrEqualTo(budget.constraints.remainingCacheExtent),
          );
          expect(hiddenPosition.pixels, initialOffset);
          expect(hiddenPosition.maxScrollExtent, initialMax);
          if (keepAlive) {
            expect(hiddenCards, greaterThanOrEqualTo(activeCards));
          } else {
            expect(hiddenCards, lessThanOrEqualTo(grid ? 4 : 1));
          }

          tabs.animateTo(0);
          await tester.pumpAndSettle();
          expect(pageKey.currentState!.controller.offset, initialOffset);
          final restored = await tester.runAsync(() => _capture(boundary));
          expect(restored, orderedEquals(before!));
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
