abstract final class DanmakuProcessingBudget {
  static const maxElementEncodedBytes = 64 * 1024;
  static const maxElementFields = 128;
  static const batchElements = 256;
  static const batchBytes = 512 * 1024;
  static const groupBytes = 8 * 1024 * 1024;
  static const normalizedBytes = 4 * 1024 * 1024;
  static const cursorBytes = groupBytes + normalizedBytes + 4096;
  static const normalizationScratchBytes = 2 * 1024 * 1024;
  static const maxDecodedBytes = 8 * 1024 * 1024;
  static const rulesBytes = 1024 * 1024;
}
