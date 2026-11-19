import 'dart:async' show unawaited;

import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/services/web_account_cookies.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/request_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' show Digest;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class LoginUtils {
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
        RequestUtils.syncHistoryStatus().catchError((
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
        SmartDialog.showToast('main登录成功');
      }
    } else {
      // 获取用户信息失败
      final errMsg = res.toString();
      if (errMsg == '账号未登录') {
        await Accounts.deleteAll({account});
        SmartDialog.showNotify(
          msg: '登录失败，请检查cookie是否正确，$errMsg',
          notifyType: .warning,
        );
      } else {
        SmartDialog.showToast(errMsg);
      }
    }
  }

  static Future<void> onLogoutMain() => Future.wait([
    WebAccountCookies.clear(),
    GStorage.userInfo.delete('userInfoCache'),
  ]);

  static String generateBuvid() {
    final md5Str = Digest(
      List.generate(16, (_) => Utils.random.nextInt(256)),
    ).toString();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  static final buvid = Pref.buvid;

  // static String getUUID() {
  //   return const Uuid().v4().replaceAll('-', '');
  // }

  static String genDeviceId() {
    // https://github.com/bilive/bilive_client/blob/2873de0532c54832f5464a4c57325ad9af8b8698/bilive/lib/app_client.ts#L62
    final time = DateTime.now();

    final List<int> bytes = [
      ...Iterable.generate(16, (_) => Utils.random.nextInt(256)),
      _dec2bcd(time.year ~/ 100),
      _dec2bcd(time.year % 100),
      _dec2bcd(time.month),
      _dec2bcd(time.day),
      _dec2bcd(time.hour),
      _dec2bcd(time.minute),
      _dec2bcd(time.second),
      ...Iterable.generate(8, (_) => Utils.random.nextInt(256)),
    ];
    final check = (bytes.sum & 0xFF).toRadixString(16).padLeft(2, '0');

    return Digest(bytes).toString() + check;
  }

  static int _dec2bcd(int dec) {
    assert(0 <= dec && dec < 100);
    return ((dec ~/ 10) << 4) | (dec % 10);
  }
}
