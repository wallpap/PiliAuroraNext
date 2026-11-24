import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';

void main() {
  testWidgets('transition only updates tab wrappers when activity changes', (
    tester,
  ) async {
    final controller = TabController(length: 6, vsync: tester);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Column(
        children: [
          for (var index = 0; index < controller.length; index++)
            TabActivity(
              controller: controller,
              index: index,
              child: const SizedBox(),
            ),
        ],
      ),
    );
    final wrappers = find.byType(TickerMode);
    var previous = tester.widgetList<TickerMode>(wrappers).toList();
    var updates = 0;
    controller.animateTo(5, duration: const Duration(milliseconds: 300));
    for (var frame = 0; frame <= 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = tester.widgetList<TickerMode>(wrappers).toList();
      for (var index = 0; index < current.length; index++) {
        if (!identical(current[index], previous[index])) updates++;
      }
      previous = current;
    }
    expect(previous.map((mode) => mode.enabled), [
      false,
      false,
      false,
      false,
      false,
      true,
    ]);
    expect(updates, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tab activity follows drag, programmatic jumps and its parent', (
    tester,
  ) async {
    final controller = TabController(length: 4, vsync: tester);
    final enabled = <int, bool>{};
    Widget scene(bool active) => TickerMode(
      enabled: active,
      child: Column(
        children: [
          for (var index = 0; index < 4; index++)
            TabActivity(
              controller: controller,
              index: index,
              child: Builder(
                builder: (context) {
                  enabled[index] = TickerMode.valuesOf(context).enabled;
                  return const SizedBox();
                },
              ),
            ),
        ],
      ),
    );
    await tester.pumpWidget(scene(true));
    expect(enabled, {0: true, 1: false, 2: false, 3: false});
    controller.offset = 0.5;
    await tester.pump();
    expect(enabled, {0: true, 1: true, 2: false, 3: false});
    controller
      ..offset = 0
      ..animateTo(3, duration: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(enabled, {0: true, 1: false, 2: false, 3: true});
    await tester.pumpAndSettle();
    expect(enabled, {0: false, 1: false, 2: false, 3: true});
    await tester.pumpWidget(scene(false));
    expect(enabled.values, everyElement(isFalse));
    await tester.pumpWidget(scene(true));
    expect(enabled[3], isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('tab activity listens only to its current controller', (
    tester,
  ) async {
    final first = TabController(length: 3, vsync: tester);
    final second = TabController(length: 3, vsync: tester, initialIndex: 1);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget scene(TabController controller, int index) => TabActivity(
      controller: controller,
      index: index,
      child: const SizedBox(),
    );

    await tester.pumpWidget(scene(first, 0));
    final mode = find.byType(TickerMode);
    expect(tester.widget<TickerMode>(mode).enabled, isTrue);
    await tester.pumpWidget(scene(second, 0));
    final inactive = tester.widget<TickerMode>(mode);
    expect(inactive.enabled, isFalse);
    first.animateTo(2);
    await tester.pumpAndSettle();
    expect(tester.widget<TickerMode>(mode), same(inactive));
    second.offset = -0.5;
    await tester.pump();
    expect(tester.widget<TickerMode>(mode).enabled, isTrue);
    await tester.pumpWidget(scene(second, 2));
    expect(tester.widget<TickerMode>(mode).enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
