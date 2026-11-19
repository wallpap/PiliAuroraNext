import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_unread.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/services/messaging/overview.dart';
import 'package:pili_aurora_next/services/settings/badge_preferences.dart';

final shellBadgesProvider = Provider.autoDispose<ShellBadges>((ref) {
  final badges = ShellBadges._(
    () => ref.read(mainAccountProvider).isLogin,
    () => ref.read(overviewHandleProvider).refresh(),
  );
  ref
    ..listen(mainAccountProvider, (_, account) {
      badges._accountChanged(account.isLogin);
    })
    ..onDispose(badges._dispose);
  return badges;
});

class ShellBadges {
  ShellBadges._(this._isLoggedIn, this._refreshMessages) {
    _preferences = BadgePreferences.changes.listen(_onPreference);
  }

  final bool Function() _isLoggedIn;
  final Future<void> Function() _refreshMessages;
  final _dynamic = DynamicUnread();
  final _dynamicMode = ValueNotifier(BadgePreferences.dynamicMode);
  final _message = ValueNotifier<MessageBadgePreferences>((
    mode: BadgePreferences.messageMode,
    types: BadgePreferences.messageTypes,
  ));
  late final StreamSubscription<BadgePreferenceChange> _preferences;

  Object? _owner;
  bool _hasDynamics = false;
  bool _hasHome = false;
  bool _started = false;
  DateTime? _lastMessageCheck;
  static const _messagePeriod = Duration(minutes: 5);

  ValueListenable<int> get dynamicCount => _dynamic.count;
  ValueListenable<DynamicBadgeMode> get dynamicMode => _dynamicMode;
  ValueListenable<MessageBadgePreferences> get message => _message;

  VoidCallback attach({
    required bool hasDynamics,
    required bool hasHome,
  }) {
    final owner = _owner = Object();
    _hasDynamics = hasDynamics;
    _hasHome = hasHome;
    _started = false;
    return () {
      if (!identical(_owner, owner)) return;
      _owner = null;
      _started = false;
      _dynamic.clear();
    };
  }

  void start({required bool onDynamics}) {
    if (_owner == null || _started) return;
    _started = true;
    if (_hasDynamics && !onDynamics && _dynamicMode.value != .hidden) {
      _dynamic.markInitialCheck();
      _refreshDynamics();
    }
    if (_hasHome && _message.value.mode != .hidden) {
      messagesOpened();
      _queryMessages();
    }
  }

  void _refreshDynamics() {
    if (_started && _hasDynamics) unawaited(_dynamic.refresh());
  }

  void clearDynamics() {
    if (_hasDynamics) _dynamic.clear();
  }

  void checkDynamics() {
    if (_started && _hasDynamics && _dynamicMode.value != .hidden) {
      unawaited(_dynamic.refreshIfDue());
    }
  }

  void messagesOpened() => _lastMessageCheck = DateTime.now();

  bool get _canQueryMessages =>
      _started &&
      _hasHome &&
      _isLoggedIn() &&
      _message.value.mode != .hidden &&
      _message.value.types.isNotEmpty;

  void _queryMessages() {
    if (_canQueryMessages) unawaited(_refreshMessages());
  }

  void checkMessages() {
    if (!_canQueryMessages) return;
    final lastCheck = _lastMessageCheck;
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) >= _messagePeriod) {
      messagesOpened();
      _queryMessages();
    }
  }

  void _onPreference(BadgePreferenceChange change) {
    switch (change) {
      case DynamicBadgeModeChanged(:final mode):
        _dynamicMode.value = mode;
        if (mode == .hidden) {
          clearDynamics();
        } else {
          _refreshDynamics();
        }
      case MessageBadgeModeChanged(:final mode):
        _message.value = (mode: mode, types: _message.value.types);
        _queryMessages();
      case MessageBadgeTypesChanged(:final types):
        _message.value = (mode: _message.value.mode, types: types);
        _queryMessages();
    }
  }

  void _accountChanged(bool isLoggedIn) {
    clearDynamics();
    if (!isLoggedIn) return;
    _queryMessages();
    if (_dynamicMode.value != .hidden) _refreshDynamics();
  }

  void _dispose() {
    unawaited(_preferences.cancel());
    _dynamic.dispose();
    _dynamicMode.dispose();
    _message.dispose();
  }
}
