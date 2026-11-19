abstract final class DanmakuSegment {
  static const durationMillis = 6 * 60 * 1000;
  static const durationMicros = durationMillis * 1000;

  static int indexAtMillis(int progress) => progress ~/ durationMillis;
}
