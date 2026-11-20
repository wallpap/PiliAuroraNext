import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

class DynamicUnread {
  final _count = ValueNotifier(0);
  int _generation = 0;
  int _lastCheckAt = 0;
  bool _disposed = false;

  ValueListenable<int> get count => _count;

  void markInitialCheck() {
    if (Pref.checkDynamic) {
      _lastCheckAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<void> refreshIfDue() async {
    if (_disposed || !Accounts.main.isLogin || !Pref.checkDynamic) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheckAt < Pref.dynamicPeriod * 60 * 1000) return;
    _lastCheckAt = now;
    await refresh();
  }

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
