import 'dart:io' show Cookie;

import 'package:pili_aurora_next/features/account/data/cookie_login_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class LoginSession {
  const LoginSession();

  bool get mainIsLoggedIn => Accounts.main.isLogin;

  Future<LoadingState<void>?> loginWithCookie(
    String input, {
    required bool Function() isCurrent,
  }) async {
    if (input.isEmpty) return const Error('cookie不能为空');
    final values = <String, String>{};
    for (final entry in input.split(';')) {
      try {
        final cookie = Cookie.fromSetCookieValue(entry.trim());
        values[cookie.name] = cookie.value;
      } on FormatException {
        continue;
      }
    }
    final mid = int.tryParse(values['DedeUserID'] ?? '');
    if (mid == null || mid <= 0) {
      return const Error('哔哩哔哩登录已失效，请重新登录');
    }
    final header = values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(';');
    final bool valid;
    try {
      valid = await CookieLoginRepository.check(header);
    } catch (error, stackTrace) {
      logger.w(
        'Cookie 登录查询失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return const Error('获取哔哩哔哩用户信息失败，可前往账号管理重试');
    }
    if (!isCurrent()) return null;
    if (!valid) return const Error('哔哩哔哩登录已失效，请重新登录');
    try {
      final account = LoginAccount(BiliCookieJar.fromJson(values), null, null);
      Accounts.replaceCredentials(account);
      await account.onChange();
      return const Success(null);
    } catch (error, stackTrace) {
      logger.w(
        '保存 Cookie 登录失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return const Error('登录失败，请检查 Cookie 后重试');
    }
  }

  Future<void> loginWithAppCredentials(Map tokenInfo, List cookieInfo) async {
    final account = LoginAccount(
      BiliCookieJar.fromList(cookieInfo),
      tokenInfo['access_token'],
      tokenInfo['refresh_token'],
    );
    Accounts.replaceCredentials(account);
    await Future.wait([?account.onChange(), AnonymousAccount().delete()]);
  }
}
