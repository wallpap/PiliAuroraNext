import 'dart:io' show Cookie;

import 'package:pili_aurora_next/features/account/data/cookie_login_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/login.dart';
import 'package:pili_aurora_next/features/account/domain/login/model.dart';
import 'package:pili_aurora_next/features/account/domain/login/result.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class LoginSession {
  const LoginSession();

  bool get mainIsLoggedIn => Accounts.main.isLogin;

  Future<LoadingState<({String authCode, String url})>> requestQr() =>
      LoginHttp.getHDcode();

  Future<LoginResult> pollQr(String authCode) => LoginHttp.codePoll(authCode);

  Future<LoginResult?> submitPassword({
    required String username,
    required String password,
    required CaptchaDataModel captcha,
    required bool Function() isCurrent,
  }) async {
    final (:challenge, :seccode, :validate, :token) = _captcha(captcha);
    final webKey = await LoginHttp.getWebKey();
    if (!isCurrent()) return null;
    if (!webKey.isSuccess) return webKey;
    final salt = webKey.data['hash'];
    if (salt is! String) {
      return LoginResult.failure('登录服务返回的数据不完整，请重试');
    }
    return LoginHttp.loginByPwd(
      username: username,
      password: password,
      key: webKey.data['key'],
      salt: salt,
      geeChallenge: challenge,
      geeSeccode: seccode,
      geeValidate: validate,
      recaptchaToken: token,
    );
  }

  Future<LoginResult?> submitSms({
    required String tel,
    required String code,
    required String captchaKey,
    required Object cid,
    required bool Function() isCurrent,
  }) async {
    final webKey = await LoginHttp.getWebKey();
    if (!isCurrent()) return null;
    if (!webKey.isSuccess) return webKey;
    return LoginHttp.loginBySms(
      tel: tel,
      code: code,
      captchaKey: captchaKey,
      cid: cid,
      key: webKey.data['key'],
    );
  }

  Future<LoginResult> requestSms({
    required String tel,
    required Object cid,
    required CaptchaDataModel captcha,
  }) => LoginHttp.sendSmsCode(
    tel: tel,
    cid: cid,
    geeChallenge: captcha.geetest?.challenge,
    geeSeccode: captcha.seccode,
    geeValidate: captcha.validate,
    recaptchaToken: captcha.token,
  );

  Future<LoginResult> requestCaptcha() => LoginHttp.preCapture();

  Future<LoginResult> getRiskAccount(Uri uri) =>
      LoginHttp.safeCenterGetInfo(tmpCode: uri.queryParameters['tmp_token']!);

  Future<LoginResult> requestRiskSms({
    required Uri uri,
    required String challenge,
    required CaptchaDataModel captcha,
  }) => LoginHttp.safeCenterSmsCode(
    tmpCode: uri.queryParameters['tmp_token']!,
    geeChallenge: challenge,
    geeSeccode: captcha.seccode,
    geeValidate: captcha.validate,
    recaptchaToken: captcha.token,
    refererUrl: uri.toString(),
  );

  Future<LoginResult> verifyRiskSms({
    required Uri uri,
    required String code,
    required String captchaKey,
  }) => LoginHttp.safeCenterSmsVerify(
    code: code,
    tmpCode: uri.queryParameters['tmp_token']!,
    requestId: uri.queryParameters['request_id']!,
    source: uri.queryParameters['source']!,
    captchaKey: captchaKey,
    refererUrl: uri.toString(),
  );

  Future<LoginResult> exchangeRiskCode(String code) =>
      LoginHttp.oauth2AccessToken(code: code);

  ({String? challenge, String? seccode, String? validate, String? token})
  _captcha(CaptchaDataModel captcha) => (
    challenge: captcha.geetest?.challenge,
    seccode: captcha.seccode,
    validate: captcha.validate,
    token: captcha.token,
  );

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
