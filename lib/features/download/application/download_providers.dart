import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/download/bili_download_entry_info.dart';
import 'package:pili_aurora_next/services/download/download_repository.dart';
import 'package:pili_aurora_next/services/download/download_service.dart';

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => throw StateError('应用入口须提供下载仓库'),
);
final downloadClientProvider = Provider<Dio>(
  (ref) => throw StateError('应用入口须提供下载客户端'),
);
final downloadBackgroundErrorProvider = Provider<void Function(String)>(
  (ref) => (_) {},
);

/// 应用级保活：最后一个页面离开后仍保留任务及调度器。
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(
    repository: ref.watch(downloadRepositoryProvider),
    downloadClient: ref.watch(downloadClientProvider),
    onBackgroundError: ref.watch(downloadBackgroundErrorProvider),
  );
  unawaited(service.initDownloadList());
  ref.onDispose(() => unawaited(service.close()));
  return service;
});

final downloadLibraryProvider =
    NotifierProvider<DownloadLibrary, LoadingState<DownloadSnapshot>>(
      DownloadLibrary.new,
    );

class DownloadLibrary extends Notifier<LoadingState<DownloadSnapshot>> {
  late DownloadService _service;

  @override
  LoadingState<DownloadSnapshot> build() {
    _service = ref.watch(downloadServiceProvider);
    void changed() => state = _snapshot();
    _service.addListener(changed);
    final service = _service;
    ref.onDispose(() => service.removeListener(changed));
    return _snapshot();
  }

  LoadingState<DownloadSnapshot> _snapshot() {
    final initialization = _service.initializationState;
    if (initialization is Error) return initialization;
    if (!initialization.isSuccess) return LoadingState.loading();
    DownloadTask capture(BiliDownloadEntryInfo entry) =>
        DownloadTask.capture(entry, generation: _service.generation);
    return Success(
      DownloadSnapshot(
        generation: _service.generation,
        completed: _service.downloadList.map(capture),
        queued: _service.waitDownloadQueue.map(capture),
        current: _service.curDownload == null
            ? null
            : capture(_service.curDownload!),
      ),
    );
  }

  Future<LoadingState<void>> refresh() => _service.initDownloadList();

  BiliDownloadEntryInfo? _resolve(DownloadTask task) {
    if (!_service.initializationState.isSuccess ||
        task.generation != _service.generation) {
      return null;
    }
    for (final entry in _service.downloadList.followedBy(
      _service.waitDownloadQueue,
    )) {
      if (identical(entry, task.identity)) return entry;
    }
    return null;
  }

  Future<LoadingState<void>> updateDanmaku(DownloadTask task) {
    final entry = _resolve(task);
    return entry == null
        ? Future.value(const DownloadCancelled())
        : _service.downloadDanmaku(entry: entry, isUpdate: true);
  }

  Future<LoadingState<void>> toggle(DownloadTask task) {
    final entry = _resolve(task);
    if (entry == null) return Future.value(const DownloadCancelled());
    return identical(_service.curDownload, entry) && entry.status.isDownloading
        ? _service.cancelDownload(isDelete: false, downloadNext: false)
        : _service.startDownload(entry);
  }

  Future<LoadingState<void>> remove(DownloadTask task) {
    final entry = _resolve(task);
    return entry == null
        ? Future.value(const DownloadCancelled())
        : _service.deleteDownload(
            entry: entry,
            removeList: true,
            removeQueue: true,
          );
  }

  Future<LoadingState<void>> removeGroup(List<DownloadTask> tasks) {
    if (tasks.isEmpty || tasks.any((task) => _resolve(task) == null)) {
      return Future.value(const DownloadCancelled());
    }
    final directory = tasks.first.pageDirPath;
    if (tasks.any((task) => task.pageDirPath != directory)) {
      return Future.value(const Error('下载分组已变化，请刷新后重试'));
    }
    return _service.deletePage(pageDirPath: directory);
  }
}
