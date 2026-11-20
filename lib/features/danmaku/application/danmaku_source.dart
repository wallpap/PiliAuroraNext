import 'dart:io' show File;

import 'package:pili_aurora_next/features/danmaku/application/work_quota.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_file_reader.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_file_store.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_segments.dart'
    as segments;
import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';

final class DanmakuSource {
  static const orderedFileWorkBytes = orderedDanmakuFileWorkBytes;

  final _orderedFile = OrderedDanmakuFileStore();

  Future<bool> updateFile(File file) => _orderedFile.updateSource(file);

  Stream<List<DanmakuElement>> readFile(
    File file, {
    required bool ordered,
    required DanmakuWorkToken token,
  }) => ordered
      ? _orderedFile.read(file, token: token)
      : readDanmakuFile(file, token: token);

  Future<bool> loadSegment({
    required int cid,
    required int segmentIndex,
    required DanmakuWorkToken workToken,
    required Future<void> Function(
      List<DanmakuElement>,
      bool,
      DanmakuWorkLease,
    )
    consume,
  }) => segments.loadDanmakuSegment(
    cid: cid,
    segmentIndex: segmentIndex,
    workToken: workToken,
    consume: consume,
  );

  Future<void> dispose() => _orderedFile.dispose();
}
