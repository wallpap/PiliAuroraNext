import 'dart:convert';

import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/login_utils.dart';

abstract final class AccountBackup {
  static String exportJson() =>
      const JsonEncoder.withIndent('    ').convert(Accounts.account.toMap());

  static Future<void> importMap(Map document) async {
    final accounts = document.map(
      (key, value) => MapEntry(key, LoginAccount.fromJson(value)),
    );
    await Accounts.account.putAll(accounts);
    await Accounts.refresh();
    if (Accounts.main.isLogin) await LoginUtils.onLoginMain();
  }
}
