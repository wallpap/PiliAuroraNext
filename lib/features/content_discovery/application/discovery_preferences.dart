import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

final hotEntrancesProvider = Provider.autoDispose<bool>((ref) {
  final subscription = GStorage.setting
      .watch(key: SettingBoxKey.showHotRcmd)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(subscription.cancel()));
  return Pref.showHotRcmd;
});

final showPgcTimelineProvider = Provider.autoDispose<bool>((ref) {
  final subscription = GStorage.setting
      .watch(key: SettingBoxKey.showPgcTimeline)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(subscription.cancel()));
  return Pref.showPgcTimeline;
});
