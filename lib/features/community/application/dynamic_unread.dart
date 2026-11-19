import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';

class DynamicUnread {
  final _count = ValueNotifier(0);
  int _generation = 0;
  bool _disposed = false;

  ValueListenable<int> get count => _count;

  Future<void> refresh() async {
    final account = Accounts.main;
    if (_disposed || !account.isLogin) return;
    final generation = ++_generation;
    try {
      final count = await const DynamicsRepository().unread(account);
      if (!_disposed &&
          generation == _generation &&
          identical(account, Accounts.main) &&
          count != null) {
        _count.value = count;
      }
    } catch (error, stackTrace) {
      logger.w('动态角标查询失败', error: error.runtimeType, stackTrace: stackTrace);
    }
  }

  void clear([int count = 0]) {
    if (_disposed) return;
    _generation++;
    _count.value = count;
  }

  void dispose() {
    _disposed = true;
    _count.dispose();
  }
}
