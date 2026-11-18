import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/download/data/download_repository.dart';
import 'package:pili_aurora_next/features/download/application/download_service.dart';

import '../../services/download/download_fixtures.dart';

class _Repository extends DownloadRepository {
  _Repository() : super(rootPath: () => 'unused');
  Future<List<BiliDownloadEntryInfo>> Function() read = () async => [];
  int loads = 0;
  @override
  Future<List<BiliDownloadEntryInfo>> load() {
    loads++;
    return read();
  }
}

Future<void> settle() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多个页面共享应用级服务，最后一个订阅退出后继续保活', () async {
    final repository = _Repository();
    final client = Dio();
    final container = ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadClientProvider.overrideWithValue(client),
      ],
    );
    final first = container.listen(downloadLibraryProvider, (_, _) {});
    final service = container.read(downloadServiceProvider);
    final second = container.listen(downloadLibraryProvider, (_, _) {});
    await settle();
    expect(repository.loads, 1);
    first.close();
    second.close();
    await container.pump();
    expect(container.exists(downloadLibraryProvider), false);
    expect(container.read(downloadServiceProvider), same(service));
    expect(service.generation, 1);
    expect(service.initializationState.isSuccess, true);
    container.dispose();
    await settle();
    expect(await service.initDownloadList(), isA<DownloadCancelled>());
    client.close(force: true);
  });

  test('仓库读取失败时列表发布错误而非旧数据，重试恢复', () async {
    final repository = _Repository()
      ..read = () async => [
        downloadEntry(completed: true)
          ..pageDirPath = 'page'
          ..entryDirPath = 'page/entry',
      ];
    final client = Dio();
    final container = ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.close(force: true);
    });
    final commands = (container..listen(downloadLibraryProvider, (_, _) {}))
        .read(downloadLibraryProvider.notifier);
    await container.read(downloadServiceProvider).waitForInitialization;
    await container.pump();
    expect(
      container.read(downloadLibraryProvider).data.completed,
      hasLength(1),
    );
    repository.read = () async =>
        throw const FileSystemException('private-path');
    await commands.refresh();
    expect(container.read(downloadLibraryProvider), isA<Error>());
    expect(container.read(downloadLibraryProvider).dataOrNull, isNull);
    repository.read = () async => [];
    await commands.refresh();
    expect(container.read(downloadLibraryProvider).data.completed, isEmpty);
  });

  test('字节进度只发布当前任务，不通知列表订阅者', () async {
    final repository = _Repository();
    final client = Dio();
    final container = ProviderContainer.test(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(() => client.close(force: true));
    final service = container.read(downloadServiceProvider);
    await service.waitForInitialization;
    final entry = downloadEntry()
      ..pageDirPath = 'page'
      ..entryDirPath = 'page/entry'
      ..status = DownloadStatus.downloading;
    service.curDownload = entry;
    final progress = <int>[];
    var publications = 0;
    container
      ..listen(downloadLibraryProvider, (_, _) => publications++)
      ..listen(downloadCurrentTaskProvider, (_, task) {
        progress.add(task!.downloadedBytes);
      });

    try {
      entry.downloadedBytes = 50;
      service.progressNotifier.notifyListeners();
      await container.pump();

      expect(progress, [50]);
      expect(publications, 0);
    } finally {
      service.curDownload = null;
    }
  });

  test('删除同步所有消费者；同路径重建或目录重读后拒绝旧任务命令', () async {
    final directory = await Directory.systemTemp.createTemp(
      'download-provider-',
    );
    final repository = DownloadRepository(rootPath: () => directory.path);
    final client = Dio();
    final original = downloadEntry(completed: true);
    await repository.create(original);
    final container = ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadClientProvider.overrideWithValue(client),
      ],
    );
    final first = <LoadingState<DownloadSnapshot>>[];
    final second = <LoadingState<DownloadSnapshot>>[];
    container
      ..listen(downloadLibraryProvider, (_, next) => first.add(next))
      ..listen(downloadLibraryProvider, (_, next) => second.add(next));
    final service = container.read(downloadServiceProvider);
    await service.waitForInitialization;
    final commands = container.read(downloadLibraryProvider.notifier);
    final old = container.read(downloadLibraryProvider).data.completed.single;
    expect((await commands.remove(old)).isSuccess, true);
    expect(first.last.data.completed, isEmpty);
    expect(second.last.data.completed, isEmpty);
    expect(old.toEntry().isCompleted, true);
    await repository.create(downloadEntry(completed: true));
    await commands.refresh();
    expect(
      container.read(downloadLibraryProvider).data.completed,
      hasLength(1),
    );
    expect(await commands.remove(old), isA<DownloadCancelled>());
    expect(await commands.updateDanmaku(old), isA<DownloadCancelled>());
    expect(await commands.toggle(old), isA<DownloadCancelled>());
    expect(await commands.removeGroup([old]), isA<DownloadCancelled>());
    expect((await repository.load()), hasLength(1));
    container.dispose();
    await settle();
    client.close(force: true);
    await directory.delete(recursive: true);
  });

  test('根作用域释放后，迟到初始化不能重新发布或启动任务', () async {
    final repository = _Repository();
    final pending = Completer<List<BiliDownloadEntryInfo>>();
    repository.read = () => pending.future;
    final client = Dio();
    final container = ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadClientProvider.overrideWithValue(client),
      ],
    );
    final service = (container..read(downloadLibraryProvider)).read(
      downloadServiceProvider,
    );
    final initialization = service.waitForInitialization;
    container.dispose();
    pending.complete([]);
    expect(await initialization, isA<DownloadCancelled>());
    await settle();
    expect(service.downloadList, isEmpty);
    expect(await service.initDownloadList(), isA<DownloadCancelled>());
    client.close(force: true);
  });
}
