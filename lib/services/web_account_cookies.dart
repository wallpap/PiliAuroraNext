import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/webview_environment.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

abstract final class WebAccountCookies {
  static Future<void> _webCookieTail = Future.value();

  // 不同账号的原生写入串行交接，避免迟到的旧 Cookie 覆盖新登录。
  static Future<T> _queueWebCookies<T>(Future<T> Function() action) {
    final result = _webCookieTail.then((_) => action());
    // 队列可以继续；调用方仍从 result 收到原始失败。
    _webCookieTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// 返回 false 表示切号后失效；原生拒绝或异常通过 Future 返回。
  static Future<bool> sync([Account? account]) {
    final owner = AccountScope.capture();
    if (account != null && !identical(account, owner.account)) {
      return Future.value(false);
    }
    return _queueWebCookies(
      () => AppWebViewEnvironment.using(() async {
        if (!owner.isCurrent) return false;
        await AppWebViewEnvironment.ensureInitialized();
        if (!owner.isCurrent) return false;
        final cookies = owner.account.cookieJar.toList();
        final webManager = web.CookieManager.instance(
          webViewEnvironment: AppWebViewEnvironment.instance,
        );
        final results = await Future.wait(
          cookies.map(
            (cookie) => webManager.setCookie(
              url: web.WebUri(
                '${Platform.isWindows ? 'https://' : ''}${cookie.domain}',
              ),
              name: cookie.name,
              value: cookie.value,
              path: cookie.path ?? '/',
              domain: cookie.domain,
              isSecure: cookie.secure,
              isHttpOnly: cookie.httpOnly,
            ),
          ),
        );
        if (results.any((success) => !success)) {
          throw const Error('网页 Cookie 同步失败，请重试');
        }
        return owner.isCurrent;
      }),
    );
  }

  static Future<void> clear() {
    final owner = AccountScope.capture();
    return _queueWebCookies(
      () => AppWebViewEnvironment.using(() async {
        if (!owner.isCurrent) return;
        await AppWebViewEnvironment.ensureInitialized();
        if (!owner.isCurrent) return;
        final cleared = await web.CookieManager.instance(
          webViewEnvironment: AppWebViewEnvironment.instance,
        ).deleteAllCookies();
        if (!cleared) throw const Error('网页 Cookie 清理失败，请重试');
      }),
    );
  }
}
