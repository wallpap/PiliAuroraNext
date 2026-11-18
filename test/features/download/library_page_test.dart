import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/download/application/download_progress.dart';
import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';
import 'package:pili_aurora_next/features/download/presentation/library_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../services/download/download_fixtures.dart';
import '../../support/memory_box.dart';

class _Progress implements DownloadProgressStore {
  final removed = <int>[];
  @override
  int? read(int cid) => null;
  @override
  Future<void> remove(Iterable<int> cids) async => removed.addAll(cids);
}

class _Current extends DownloadCurrentTask {
  _Current(this.initial);
  final DownloadTaskProgress initial;
  @override
  DownloadTaskProgress? build() => initial;
  void publish(DownloadTaskProgress progress) => state = progress;
}

class _Library extends DownloadLibrary {
  _Library(this.initial);
  final DownloadSnapshot initial;
  final removals = <DownloadTask>[];
  final replies = <Completer<LoadingState<void>>>[];
  @override
  LoadingState<DownloadSnapshot> build() => Success(initial);
  void publish(DownloadSnapshot snapshot) => state = Success(snapshot);
  @override
  Future<T> withoutAutomaticScheduling<T>(Future<T> Function() operation) =>
      operation();
  @override
  Future<LoadingState<void>> remove(DownloadTask task) async {
    removals.add(task);
    final reply = Completer<LoadingState<void>>();
    replies.add(reply);
    final result = await reply.future;
    if (result.isSuccess) {
      publish(
        DownloadSnapshot(
          completed: state.data.completed.where(
            (item) => !identical(item.identity, task.identity),
          ),
          queued: [],
          current: null,
        ),
      );
    }
    return result;
  }
}

DownloadTask task(int cid) {
  final json = downloadEntry(aid: cid, cid: cid, completed: true).toJson()
    ..['cover'] = '';
  final entry = BiliDownloadEntryInfo.fromJson(json)
    ..pageDirPath = 'page-$cid'
    ..entryDirPath = 'page-$cid/entry';
  return DownloadTask.capture(entry);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GStorage.setting = MemoryBox());
  tearDown(Get.reset);

  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container,
    Widget page,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: GetMaterialApp(builder: FlutterSmartDialog.init(), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('详情独立打开并订阅共享列表，不依赖下载首页 controller', (tester) async {
    final a = task(1);
    final library = _Library(
      DownloadSnapshot(completed: [a], queued: [], current: null),
    );
    final container = ProviderContainer(
      overrides: [
        downloadLibraryProvider.overrideWith(() => library),
        downloadProgressStoreProvider.overrideWithValue(_Progress()),
      ],
    );
    addTearDown(container.dispose);
    await mount(
      tester,
      container,
      const DownloadLibraryPage(
        mode: DownloadViewMode.detail,
        pageId: '1',
        title: '离线详情',
      ),
    );
    expect(find.text('测试下载'), findsOneWidget);
    library.publish(DownloadSnapshot(completed: [], queued: [], current: null));
    await tester.pumpAndSettle();
    expect(find.text('测试下载'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('当前任务行显示订阅到的字节进度', (tester) async {
    final entry =
        BiliDownloadEntryInfo.fromJson(downloadEntry().toJson()..['cover'] = '')
          ..pageDirPath = 'page'
          ..entryDirPath = 'page/entry'
          ..status = DownloadStatus.downloading;
    final initial = DownloadTask.capture(entry);
    final snapshot = DownloadSnapshot(
      completed: [],
      queued: [initial],
      current: initial,
    );
    final library = _Library(snapshot);
    DownloadTaskProgress progress({Object? identity, int? generation}) => (
      identity: identity ?? entry,
      generation: generation ?? initial.generation,
      status: entry.status,
      downloadedBytes: entry.downloadedBytes,
      totalBytes: entry.totalBytes,
    );
    final current = _Current(progress());
    final container = ProviderContainer(
      overrides: [
        downloadLibraryProvider.overrideWith(() => library),
        downloadCurrentTaskProvider.overrideWith(() => current),
        downloadProgressStoreProvider.overrideWithValue(_Progress()),
      ],
    );
    addTearDown(container.dispose);
    await mount(
      tester,
      container,
      const DownloadLibraryPage(mode: DownloadViewMode.queued),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.1,
    );
    entry.downloadedBytes = 50;
    current.publish(progress(identity: Object()));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.1,
    );
    current.publish(progress(generation: initial.generation + 1));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.1,
    );
    current.publish(progress());
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('搜索批量部分失败保留失败项选择，成功项同步删除并清理进度', (tester) async {
    final a = task(1);
    final b = task(2);
    final library = _Library(
      DownloadSnapshot(completed: [a, b], queued: [], current: null),
    );
    final progress = _Progress();
    final container = ProviderContainer(
      overrides: [
        downloadLibraryProvider.overrideWith(() => library),
        downloadProgressStoreProvider.overrideWithValue(progress),
      ],
    );
    addTearDown(container.dispose);
    await mount(
      tester,
      container,
      const DownloadLibraryPage(mode: DownloadViewMode.search),
    );
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选: 2'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(library.removals, isEmpty);
    expect(find.text('已选: 2'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pump();
    expect(library.removals, [a]);
    library.replies[0].complete(const Error('删除失败，请重试'));
    await tester.pump();
    expect(library.removals, [a, b]);
    library.replies[1].complete(const Success(null));
    await tester.pump();
    await tester.pump();
    expect(find.text('已选: 1'), findsOneWidget);
    expect(container.read(downloadLibraryProvider).data.completed, [a]);
    expect(progress.removed, [2]);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('同一份任务在两个页面中的选择互不影响，刷新目录清除旧选择', (tester) async {
    final library = _Library(
      DownloadSnapshot(completed: [task(1)], queued: [], current: null),
    );
    final container = ProviderContainer(
      overrides: [
        downloadLibraryProvider.overrideWith(() => library),
        downloadProgressStoreProvider.overrideWithValue(_Progress()),
      ],
    );
    addTearDown(container.dispose);
    await mount(tester, container, const DownloadLibraryPage());
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选: 1'), findsOneWidget);
    Get.to(
      () => const DownloadLibraryPage(
        mode: DownloadViewMode.detail,
        pageId: '1',
        title: '独立详情',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('独立详情'), findsOneWidget);
    expect(find.text('已选: 1'), findsNothing);
    Get.back();
    await tester.pumpAndSettle();
    expect(find.text('已选: 1'), findsOneWidget);
    library.publish(
      DownloadSnapshot(
        generation: 1,
        completed: [task(1)],
        queued: [],
        current: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选: 1'), findsNothing);
    expect(find.text('离线缓存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
