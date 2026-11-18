import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/pages/danmaku/merge.dart';

void main() {
  test('font growth respects switch, threshold, speed and bounds', () {
    double scale(
      int count, {
      bool enabled = true,
      int threshold = 7,
      double base = 7,
    }) => mergedDanmakuFontScale(
      count,
      enabled: enabled,
      threshold: threshold,
      logBase: base,
    );
    expect(scale(7), 1);
    expect(scale(8), greaterThan(1));
    expect(scale(49), closeTo(2, 0.0001));
    expect(scale(100000), 2);
    expect(scale(100, enabled: false), 1);
    expect(scale(4, threshold: 2, base: 7), 1);
    expect(scale(10, base: 3), greaterThan(scale(10)));
  });
}
