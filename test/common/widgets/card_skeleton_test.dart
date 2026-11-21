import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/skeleton/skeleton.dart';
import 'package:pili_aurora_next/common/skeleton/video_card_v.dart';

class _CountingPainter extends CustomPainter {
  var paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

void main() {
  testWidgets('扫光复用静态绘制，隐藏或减少动态效果时停止调度', (tester) async {
    final painter = _CountingPainter();
    Widget scene({bool active = true, bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: TickerMode(
        enabled: active,
        child: Skeleton(child: CustomPaint(painter: painter)),
      ),
    );

    await tester.pumpWidget(scene());
    expect(painter.paints, greaterThan(0));
    final initial = painter.paints;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter.paints, initial);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(scene(active: false));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(reduceMotion: true));
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byType(CustomPaint), findsOneWidget);
    await tester.pumpWidget(scene());
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('骨架网格的扫光改变画面，连续帧复用卡片子树', (tester) async {
    const firstCard = ValueKey('first-card');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: 195,
          ),
          itemCount: 12,
          itemBuilder: (_, index) => index == 0
              ? const RepaintBoundary(
                  key: firstCard,
                  child: VideoCardVSkeleton(),
                )
              : const VideoCardVSkeleton(),
        ),
      ),
    );
    expect(find.byType(VideoCardVSkeleton), findsNWidgets(12));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(firstCard),
    );
    Future<List<int>> pixels() async {
      final image = boundary.toImageSync();
      try {
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        return bytes!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    await tester.pump(const Duration(milliseconds: 100));
    final before = await pixels();
    var builds = 0;
    final previous = debugOnRebuildDirtyWidget;
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.findAncestorWidgetOfExactType<VideoCardVSkeleton>() != null) {
        builds++;
      }
    };
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    final after = await pixels();
    expect(listEquals(after, before), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(builds, 0);
  });
}
