import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/features/playback/application/offline_progress.dart';
import 'package:pili_aurora_next/features/playback/domain/media/offline_watch_progress.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

void main() {
  const cid = 17;
  setUpAll(() async {
    GStorage.watchProgress = await Hive.openBox<int>(
      'offline-progress-test',
      bytes: Uint8List(0),
    );
  });
  tearDown(() => GStorage.watchProgress.clear());
  tearDownAll(Hive.close);

  test('完播与时长无关，且新位置和新完播可以互相覆盖', () async {
    await OfflineProgress.record(cid, const OfflineWatchProgress.completed());
    for (final duration in [0, 100000, 120000]) {
      expect(OfflineProgress.read(cid, duration)?.isCompleted, isTrue);
      expect(OfflineProgress.resume(cid, duration), Duration.zero);
    }

    await OfflineProgress.record(cid, const OfflineWatchProgress.at(99800));
    expect(OfflineProgress.read(cid, 100000)?.isCompleted, isFalse);
    expect(OfflineProgress.resume(cid, 100000).inMilliseconds, 99800);
    expect(OfflineProgress.resume(cid, 99800), Duration.zero);
    await OfflineProgress.record(cid, const OfflineWatchProgress.completed());
    expect(OfflineProgress.resume(cid, 120000), Duration.zero);
  });

  test('未知或非正时长不截断位置，零位置不等于完播', () async {
    await OfflineProgress.record(cid, const OfflineWatchProgress.at(12000));
    for (final duration in [0, -1]) {
      expect(OfflineProgress.resume(cid, duration).inMilliseconds, 12000);
    }
    await OfflineProgress.record(cid, const OfflineWatchProgress.at(0));
    expect(OfflineProgress.read(cid, 0)?.isCompleted, isFalse);
  });

  test('旧记录按原规则回退，新记录优先，删除同时清除两代记录', () async {
    await GStorage.watchProgress.put('$cid', 99800);
    expect(OfflineProgress.read(cid, 100000)?.isCompleted, isTrue);
    expect(OfflineProgress.resume(cid, 0).inMilliseconds, 99800);
    await OfflineProgress.record(cid, const OfflineWatchProgress.at(12000));
    expect(OfflineProgress.resume(cid, 100000).inMilliseconds, 12000);
    await OfflineProgress.remove([cid]);
    expect(OfflineProgress.read(cid, 100000), isNull);
    expect(GStorage.watchProgress.isEmpty, isTrue);
  });
}
