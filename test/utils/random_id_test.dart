import 'dart:math';

import 'package:pili_aurora_next/utils/random_id.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UUID v4 uses lowercase canonical form and the RFC variant', () {
    final random = Random(42);
    final values = [
      for (var index = 0; index < 16; index++) newUuidV4(random: random),
    ];
    expect(values.toSet(), hasLength(values.length));
    expect(
      values,
      everyElement(
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('Buvid3 preserves uppercase UUID, five digit suffix and infoc', () {
    final value = IdUtils.genBuvid3();
    expect(
      RegExp(
        r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}\d{5}infoc$',
      ).hasMatch(value),
      isTrue,
    );
  });
}
