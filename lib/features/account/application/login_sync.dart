import 'dart:async' show unawaited;

import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/feedback/user_notice.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/account/application/web_account_cookies.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

abstract final class LoginSync {
  static Future<void> onLoginMain() async {
    final account = Accounts.main;
    final receipt = await AccountProfile.legacy.confirmLogin(account);
    if (receipt == null) return;
    final res = receipt.result;
    if (!identical(account, Accounts.main)) return;
    if (res case Success(:final response)) {
      if (receipt.cacheError case final error?) {
        logger.w('登录资料缓存保存失败', error: error.runtimeType);
      }
      unawaited(
        WebAccountCookies.sync(account)
            .catchError((Object error, StackTrace stackTrace) {
              logger.w(
                '登录后的网页 Cookie 同步失败',
                error: error.runtimeType,
                stackTrace: stackTrace,
              );
              return false;
            }),
      );
      unawaited(
        HistoryLibrary.legacy.syncActiveAccountStatus().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          logger.w(
            '登录后的历史状态同步失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        }),
      );
      if (response.isLogin == true) {
        UserNotice.toast('main登录成功');
      }
    } else {
      // 获取用户信息失败
      final errMsg = res.toString();
      if (errMsg == '账号未登录') {
        await Accounts.deleteAll({account});
        UserNotice.warning('登录失败，请检查cookie是否正确，$errMsg');
      } else {
        UserNotice.toast(errMsg);
      }
    }
  }

  static Future<void> onLogoutMain() => Future.wait([
    WebAccountCookies.clear(),
    GStorage.userInfo.delete('userInfoCache'),
  ]);
}
