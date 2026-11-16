import 'package:pili_aurora_next/features/download/domain/download_entry.dart';

/// 页面只读取副本；命令凭原始对象身份核对记录，避免同路径重建后操作新任务。
class DownloadTask {
  DownloadTask.capture(BiliDownloadEntryInfo entry, {this.generation = 0})
    : identity = entry,
      _entry = _copy(entry);

  final Object identity;
  final int generation;
  final BiliDownloadEntryInfo _entry;

  String get key => _entry.entryDirPath;
  String get pageId => _entry.pageId;
  String get pageDirPath => _entry.pageDirPath;
  int get sortKey => _entry.sortKey;
  int get cid => _entry.cid;
  String get title => _entry.title;
  String get showTitle => _entry.showTitle;
  String? get ownerName => _entry.ownerName;
  DownloadStatus get status => _entry.status;
  int get downloadedBytes => _entry.downloadedBytes;
  int get totalBytes => _entry.totalBytes;

  BiliDownloadEntryInfo toEntry() => _copy(_entry);

  static BiliDownloadEntryInfo _copy(BiliDownloadEntryInfo entry) =>
      BiliDownloadEntryInfo.fromJson(entry.toJson())
        ..pageDirPath = entry.pageDirPath
        ..entryDirPath = entry.entryDirPath
        ..status = entry.status;
}

class DownloadSnapshot {
  DownloadSnapshot({
    this.generation = 0,
    required Iterable<DownloadTask> completed,
    required Iterable<DownloadTask> queued,
    required this.current,
  }) : completed = List.unmodifiable(completed),
       queued = List.unmodifiable(queued);

  final List<DownloadTask> completed;
  final int generation;
  final List<DownloadTask> queued;
  final DownloadTask? current;

  List<DownloadTask> entriesFor(String pageId) => List.unmodifiable(
    completed.where((task) => task.pageId == pageId).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
  );

  List<DownloadTask> search(String query) {
    final text = query.trim().toLowerCase();
    return List.unmodifiable(
      completed.where(
        (task) =>
            task.title.toLowerCase().contains(text) ||
            task.showTitle.toLowerCase().contains(text) ||
            (task.ownerName?.toLowerCase().contains(text) ?? false),
      ),
    );
  }
}
