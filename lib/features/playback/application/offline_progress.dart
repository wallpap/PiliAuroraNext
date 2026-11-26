import 'package:pili_aurora_next/features/playback/domain/media/offline_watch_progress.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

abstract final class OfflineProgress {
  static const _completedValue = -1;
  static String _key(int cid) => 'v2:$cid';

  static OfflineWatchProgress? read(int cid, int durationMs) {
    final stored = GStorage.watchProgress.get(_key(cid));
    if (stored == _completedValue)
      return const OfflineWatchProgress.completed();
    if (stored != null) {
      return stored < 0 ? null : OfflineWatchProgress.at(stored);
    }
    final legacy = GStorage.watchProgress.get('$cid');
    if (legacy == null || legacy < 0) return null;
    return durationMs > 0 && legacy >= durationMs - 400
        ? const OfflineWatchProgress.completed()
        : OfflineWatchProgress.at(legacy);
  }

  static Duration resume(int cid, int durationMs) {
    final position = read(cid, durationMs)?.positionMs;
    if (position == null || (durationMs > 0 && position >= durationMs)) {
      return Duration.zero;
    }
    return Duration(milliseconds: position);
  }

  static Future<void> record(int cid, OfflineWatchProgress progress) async {
    final position = progress.positionMs;
    if (cid <= 0 || (position != null && position < 0)) return;
    try {
      await GStorage.watchProgress.put(_key(cid), position ?? _completedValue);
    } catch (error, stackTrace) {
      logger.w(
        '保存离线播放进度失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> remove(Iterable<int> cids) => GStorage.watchProgress
      .deleteAll(cids.expand((cid) => ['$cid', _key(cid)]));
}
