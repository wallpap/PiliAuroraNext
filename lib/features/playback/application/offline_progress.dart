import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/storage.dart';

abstract final class OfflineProgress {
  static Duration resume(int cid, int durationMs) {
    final position = GStorage.watchProgress.get(cid.toString());
    if (position == null || position < 0 || position >= durationMs - 400) {
      return Duration.zero;
    }
    return Duration(milliseconds: position);
  }

  static Future<void> record(int cid, int positionMs) async {
    if (cid <= 0 || positionMs < 0) return;
    try {
      await GStorage.watchProgress.put(cid.toString(), positionMs);
    } catch (error, stackTrace) {
      logger.w(
        '保存离线播放进度失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
    }
  }
}
