import 'dart:convert' show base64;

import 'package:pili_aurora_next/core/random/random_text.dart';

String randomFingerprint(int minLength, int maxLength) {
  final bytes = List<int>.generate(
    minLength + sharedRandom.nextInt(maxLength - minLength + 1),
    (_) => 0x26 + sharedRandom.nextInt(0x59),
  );
  final encoded = base64.encode(bytes);
  return encoded.substring(0, encoded.length - 2);
}
