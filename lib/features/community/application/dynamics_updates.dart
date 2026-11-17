import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef DynamicsChange = ({
  Account account,
  String? removed,
  ({String id, bool pinned})? pin,
});

/// 发布入口与列表共用失效事件，不保留第二份动态列表。
class DynamicsUpdates {
  static final shared = DynamicsUpdates();
  final _changes = StreamController<DynamicsChange>.broadcast(
    sync: true,
  );
  Stream<DynamicsChange> get changes => _changes.stream;
  void published(Account account) =>
      _changes.add((account: account, removed: null, pin: null));
  void removed(Account account, String id) =>
      _changes.add((account: account, removed: id, pin: null));
  void pinned(Account account, String id, bool pinned) => _changes.add((
    account: account,
    removed: null,
    pin: (id: id, pinned: pinned),
  ));
  Future<void> close() => _changes.close();
}

final dynamicsUpdatesProvider = Provider((ref) => DynamicsUpdates.shared);
