import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/playback/domain/media/offline_watch_progress.dart';

/// 播放进度的存储适配由应用入口提供，页面不直接访问全局 Hive。
abstract interface class DownloadProgressStore {
  OfflineWatchProgress? read(int cid, int durationMs);
  Future<void> remove(Iterable<int> cids);
}

final downloadProgressStoreProvider = Provider<DownloadProgressStore>(
  (ref) => throw StateError('应用入口须提供离线播放进度存储'),
);
