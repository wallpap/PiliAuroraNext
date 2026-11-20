import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class CookieLoginRepository {
  static Future<bool> check(String cookie) async {
    final result = await Request().get(
      '/x/member/web/account',
      options: Options(
        headers: {'cookie': cookie},
        extra: {'account': AnonymousAccount()},
      ),
    );
    return result.data['code'] == 0;
  }
}
