import 'dart:math' show Random;

final sharedRandom = Random();

String generateRandomString(int length) {
  const characters = '0123456789abcdefghijklmnopqrstuvwxyz';
  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => characters.codeUnitAt(sharedRandom.nextInt(characters.length)),
    ),
  );
}
