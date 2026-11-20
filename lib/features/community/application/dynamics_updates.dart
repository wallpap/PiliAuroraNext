import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef DynamicsChange = ({
  Account account,
  String? removed,
  ({String id, bool pinned})? pin,
});

/// 发布入口与列表共用失效事件，不保留第二份动态列表。
class DynamicsUpdates {
  final _changes = StreamController<DynamicsChange>.broadcast(
    sync: true,
  );
  Stream<DynamicsChange> get changes => _changes.stream;
  void published(Account account) =>
      _emit((account: account, removed: null, pin: null));
  void removed(Account account, String id) =>
      _emit((account: account, removed: id, pin: null));
  void pinned(Account account, String id, bool pinned) => _emit((
    account: account,
    removed: null,
    pin: (id: id, pinned: pinned),
  ));
  void _emit(DynamicsChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  Future<void> close() => _changes.close();
}

final dynamicsUpdatesProvider = Provider((ref) {
  final updates = DynamicsUpdates();
  ref.onDispose(() => unawaited(updates.close()));
  return updates;
});
