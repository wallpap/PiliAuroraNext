import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';

Widget _observeActivity(void Function(bool) report) => Builder(
  builder: (context) {
    report(TickerMode.valuesOf(context).enabled);
    return const SizedBox();
  },
);

void main() {
  testWidgets('tab activity follows drag, programmatic jumps and its parent', (
    tester,
  ) async {
    final controller = TabController(length: 4, vsync: tester);
    addTearDown(controller.dispose);
    final enabled = <int, bool>{};
    Widget scene(bool active) => TickerMode(
      enabled: active,
      child: Column(
        children: [
          for (var index = 0; index < 4; index++)
            TabActivity(
              controller: controller,
              index: index,
              child: _observeActivity(
                (active) => enabled[index] = active,
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
      ..animateTo(3, duration: const Duration(milliseconds: 300));
    await tester.pump();
    for (var step = 0; step < 5; step++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(enabled, {0: true, 1: false, 2: false, 3: true});
    }
    await tester.pumpAndSettle();
    expect(enabled, {0: false, 1: false, 2: false, 3: true});
    await tester.pumpWidget(scene(false));
    expect(enabled.values, everyElement(isFalse));
    await tester.pumpWidget(scene(true));
    expect(enabled[3], isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tab activity follows the replacement controller and index', (
    tester,
  ) async {
    final first = TabController(length: 3, vsync: tester);
    final second = TabController(length: 3, vsync: tester, initialIndex: 1);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    late bool active;

    Widget scene(TabController controller, int index) => TabActivity(
      controller: controller,
      index: index,
      child: _observeActivity((value) => active = value),
    );

    await tester.pumpWidget(scene(first, 0));
    expect(active, isTrue);
    await tester.pumpWidget(scene(second, 0));
    expect(active, isFalse);
    first.animateTo(2, duration: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(active, isFalse);
    second.offset = -0.5;
    await tester.pump();
    expect(active, isTrue);
    await tester.pumpWidget(scene(second, 2));
    expect(active, isFalse);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
