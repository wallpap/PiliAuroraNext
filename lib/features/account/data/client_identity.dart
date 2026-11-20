import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' show Digest;
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/utils.dart';

abstract final class ClientIdentity {
  static final buvid = Pref.buvid;

  static String generateBuvid() {
    final md5Str = Digest(
      List.generate(16, (_) => Utils.random.nextInt(256)),
    ).toString();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  static String generateDeviceId() {
    final time = DateTime.now();
    final bytes = <int>[
      ...Iterable.generate(16, (_) => Utils.random.nextInt(256)),
      _decimalToBcd(time.year ~/ 100),
      _decimalToBcd(time.year % 100),
      _decimalToBcd(time.month),
      _decimalToBcd(time.day),
      _decimalToBcd(time.hour),
      _decimalToBcd(time.minute),
      _decimalToBcd(time.second),
      ...Iterable.generate(8, (_) => Utils.random.nextInt(256)),
    ];
    final check = (bytes.sum & 0xFF).toRadixString(16).padLeft(2, '0');
    return Digest(bytes).toString() + check;
  }

  static int _decimalToBcd(int value) {
    assert(0 <= value && value < 100);
    return ((value ~/ 10) << 4) | (value % 10);
  }
}
