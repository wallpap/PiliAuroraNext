import 'dart:convert';

import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/application/login_sync.dart';

abstract final class AccountBackup {
  static String exportJson() =>
      const JsonEncoder.withIndent('    ').convert(Accounts.account.toMap());

  static Future<void> importMap(Map document) async {
    final accounts = document.map(
      (key, value) => MapEntry(key, LoginAccount.fromJson(value)),
    );
    await Accounts.account.putAll(accounts);
    await Accounts.refresh();
    if (Accounts.main.isLogin) await LoginSync.onLoginMain();
  }
}
