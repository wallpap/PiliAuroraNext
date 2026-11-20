import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/login.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class AccountLogout {
  AccountLogout(Set<LoginAccount> selected) : result = Set.of(selected);

  static List<LoginAccount> get candidates =>
      List.unmodifiable(Accounts.account.values);
  static bool get hasMainAccount => Accounts.main.isLogin;

  final Set<LoginAccount> result;
  final _confirmed = Set<LoginAccount>.identity();
  final messages = <LoginAccount, String>{};
  String? cleanupWarning;

  Future<bool> submit({required bool revoke}) async {
    cleanupWarning = null;
    if (!revoke) return _cleanup(Set.of(result));
    final targets = result.where((account) => !_confirmed.contains(account));
    final outcomes = await Future.wait(
      targets.map((account) async {
        return (account, await _logoutWrapper(account));
      }),
    );
    for (final (account, outcome) in outcomes) {
      if (outcome.isSuccess) {
        _confirmed.add(account);
        messages.remove(account);
      } else {
        messages[account] = outcome.toString();
      }
    }
    return _cleanup(result.where(_confirmed.contains).toSet());
  }

  Future<bool> _cleanup(Set<LoginAccount> accounts) async {
    final current = <LoginAccount>{};
    for (final account in accounts) {
      if (_isStoredLogin(account)) {
        current.add(account);
      } else {
        messages[account] = _confirmed.contains(account)
            ? '远端已退出，登录信息已更新，请核对'
            : '登录信息已更新，请重新选择';
      }
    }
    if (current.isEmpty) return false;
    try {
      await Accounts.deleteAll(current);
    } catch (error, stackTrace) {
      logger.w(
        '退出登录后的本地清理失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      cleanupWarning = '账号已登出，部分本地清理失败，请重启后核对';
    }
    for (final account in current) {
      final remaining = Accounts.account.values.where(
        (stored) => stored.mid == account.mid,
      );
      if (remaining.isEmpty) {
        result.remove(account);
        messages.remove(account);
      } else if (remaining.any((stored) => identical(stored, account))) {
        messages[account] = _confirmed.contains(account)
            ? '远端已退出，本地清理失败；再次确认将仅重试清理'
            : '本地清理失败，请重试';
      } else {
        messages[account] = _confirmed.contains(account)
            ? '远端已退出，登录信息已更新，请核对'
            : '登录信息已更新，请重新选择';
      }
    }
    return true;
  }
}

bool _isStoredLogin(LoginAccount account) =>
    Accounts.account.values.any((value) => identical(value, account));

Future<LoadingState<void>> _logoutWrapper(LoginAccount account) async {
  if (!_isStoredLogin(account)) {
    return const Error('登录信息已更新，请重新选择');
  }
  try {
    return await LoginHttp.logout(account);
  } catch (error, stackTrace) {
    logger.w('退出登录请求失败', error: error.runtimeType, stackTrace: stackTrace);
    return UnknownResult(cause: error, stackTrace: stackTrace);
  }
}
