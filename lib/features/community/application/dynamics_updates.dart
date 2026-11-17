import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

/// 发布入口与列表共用失效事件，不保留第二份动态列表。
class DynamicsUpdates {
  static final shared = DynamicsUpdates();
  final _changes =
      StreamController<({Account account, String? removed})>.broadcast(
        sync: true,
      );
  Stream<({Account account, String? removed})> get changes => _changes.stream;
  void published(Account account) =>
      _changes.add((account: account, removed: null));
  void removed(Account account, String id) =>
      _changes.add((account: account, removed: id));
  Future<void> close() => _changes.close();
}

final dynamicsUpdatesProvider = Provider((ref) => DynamicsUpdates.shared);
