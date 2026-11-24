import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_chart.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/memory_box.dart';

void main() {
  setUpAll(() => GStorage.setting = MemoryBox<dynamic>());

  testWidgets('switching trends renders the new curve without a ticker', (
    tester,
  ) async {
    Future<void> showTrend(List<double> trend) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            child: DanmakuTrendChart(
              themeColor: Colors.blue,
              trend: trend,
              bottom: 4,
            ),
          ),
        ),
      ),
    );

    await showTrend([1, 3, 2]);
    await tester.pumpAndSettle();
    await showTrend([2, 6, 4, 3]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.map((spot) => spot.y), [
      2,
      6,
      4,
      3,
    ]);
    expect(chart.data.maxY, 6);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
