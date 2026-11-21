import 'dart:math';

final _secureRandom = Random.secure();

String newUuidV4({Random? random}) {
  final source = random ?? _secureRandom;
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final result = StringBuffer();
  for (var index = 0; index < bytes.length; index++) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      result.write('-');
    }
    result.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  return result.toString();
}
