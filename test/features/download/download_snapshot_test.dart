import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';

import '../../services/download/download_fixtures.dart';

void main() {
  test('任务快照与服务及调用方的可变记录隔离', () {
    final entry = downloadEntry()
      ..pageDirPath = 'page'
      ..entryDirPath = 'page/entry';
    final task = DownloadTask.capture(entry);
    entry.downloadedBytes = 99;
    entry.pageData!.width = 1920;
    expect(task.downloadedBytes, 10);
    expect(task.toEntry().pageData!.width, 0);
    task.toEntry().downloadedBytes = 55;
    expect(task.downloadedBytes, 10);
    expect(task.identity, same(entry));
  });

  test('列表、分组和搜索快照不可修改，输入列表后续变化不回写', () {
    final entry = downloadEntry(completed: true)
      ..pageDirPath = 'page'
      ..entryDirPath = 'page/entry';
    final tasks = [DownloadTask.capture(entry)];
    final snapshot = DownloadSnapshot(
      completed: tasks,
      queued: [],
      current: null,
    );
    tasks.clear();
    expect(snapshot.completed, hasLength(1));
    expect(snapshot.entriesFor(entry.pageId), hasLength(1));
    expect(snapshot.search(entry.title.toUpperCase()), hasLength(1));
    expect(snapshot.search('不存在'), isEmpty);
    expect(() => snapshot.completed.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.entriesFor(entry.pageId).clear(),
      throwsUnsupportedError,
    );
  });
}

