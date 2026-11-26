final class OfflineWatchProgress {
  const OfflineWatchProgress.completed() : positionMs = null;
  const OfflineWatchProgress.at(int this.positionMs);

  final int? positionMs;
  bool get isCompleted => positionMs == null;
}
