import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/models/common/theme/theme_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class AccountPrivacy {
  static bool get canEnable => Accounts.account.values.isNotEmpty;
  static bool get enabled => canEnable && !Accounts.heartbeat.isLogin;
  static Account get owner => Accounts.main;
  static bool owns(Account account) => identical(owner, account);
  static void enableTemporarily() =>
      Accounts.setTemporaryHeartbeat(AnonymousAccount());
  static Future<void> saveEnabled() =>
      Accounts.set(AccountType.heartbeat, AnonymousAccount());
  static Future<void> disable() =>
      Accounts.set(AccountType.heartbeat, Accounts.main);
}

final incognitoProvider = NotifierProvider<IncognitoNotifier, bool>(
  IncognitoNotifier.new,
  isAutoDispose: true,
);

class IncognitoNotifier extends Notifier<bool> {
  @override
  bool build() {
    void changed() => state = AccountPrivacy.enabled;
    Accounts.heartbeatChanges.addListener(changed);
    Accounts.mainChanges.addListener(changed);
    ref.onDispose(() {
      Accounts.heartbeatChanges.removeListener(changed);
      Accounts.mainChanges.removeListener(changed);
    });
    return AccountPrivacy.enabled;
  }
}

final accountThemeProvider = NotifierProvider<AccountThemeNotifier, ThemeType>(
  AccountThemeNotifier.new,
  isAutoDispose: true,
);

class AccountThemeNotifier extends Notifier<ThemeType> {
  @override
  ThemeType build() {
    final subscription = GStorage.setting
        .watch(key: SettingBoxKey.themeMode)
        .listen((_) => state = Pref.themeType);
    ref.onDispose(() => unawaited(subscription.cancel()));
    return Pref.themeType;
  }

  Future<ThemeType> next() async {
    final next = ThemeType.values[(state.index + 1) % ThemeType.values.length];
    await GStorage.setting.put(SettingBoxKey.themeMode, next.index);
    return next;
  }
}
