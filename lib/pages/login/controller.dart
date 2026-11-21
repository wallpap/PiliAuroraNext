import 'dart:async';

import 'package:pili_aurora_next/common/dial_prefix.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/features/account/presentation/account_switch_dialog.dart';
import 'package:pili_aurora_next/features/account/application/login_session.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/login/model.dart';
import 'package:pili_aurora_next/pages/login/geetest/geetest_webview_dialog.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LoginPageController {
  static const _session = LoginSession();
  final TextEditingController telTextController = TextEditingController();
  final TextEditingController usernameTextController = TextEditingController();
  final TextEditingController passwordTextController = TextEditingController();
  final TextEditingController smsCodeTextController = TextEditingController();
  final TextEditingController cookieTextController = TextEditingController();

  final codeInfo = ValueNotifier<LoadingState<({String authCode, String url})>>(
    LoadingState.loading(),
  );

  late final TabController tabController;

  late final CaptchaDataModel captchaData = CaptchaDataModel();
  final qrCodeLeftTime = ValueNotifier(180);
  final statusQRCode = ValueNotifier('');

  late var selectedCountryCodeId = Login.dialPrefix.first;
  late String captchaKey = '';
  final smsSendCooldown = ValueNotifier(0);
  final smsSending = ValueNotifier(false);
  late int smsSendTimestamp = 0;
  ({String tel, Object country})? _smsRecipient;

  // 定时器
  Timer? qrCodeTimer;
  Timer? smsSendCooldownTimer;

  bool _isReq = false;
  int _qrGeneration = 0;
  int _smsLoginGeneration = 0;
  int _passwordGeneration = 0;
  int _lastTabIndex = 0;

  bool _closed = false;
  bool get isClosed => _closed;

  void attach(TickerProvider vsync) {
    tabController = TabController(length: 4, vsync: vsync)
      ..addListener(_handleTabChange);
  }

  void dispose() {
    _closed = true;
    tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    qrCodeTimer?.cancel();
    _qrGeneration++;
    _smsLoginGeneration++;
    smsSendCooldownTimer?.cancel();
    smsSending.value = false;
    smsSending.dispose();
    smsSendCooldown.dispose();
    codeInfo.dispose();
    qrCodeLeftTime.dispose();
    statusQRCode.dispose();
    telTextController.dispose();
    usernameTextController.dispose();
    passwordTextController.dispose();
    smsCodeTextController.dispose();
    cookieTextController.dispose();
  }

  Future<void> refreshQRCode() async {
    if (isClosed) return;
    final generation = ++_qrGeneration;
    qrCodeTimer?.cancel();
    _isReq = false;
    codeInfo.value = LoadingState.loading();
    qrCodeLeftTime.value = 180;
    statusQRCode.value = '';
    late final LoadingState<({String authCode, String url})> res;
    try {
      res = await _session.requestQr();
    } catch (_) {
      if (!isClosed && generation == _qrGeneration) {
        codeInfo.value = const Error('二维码申请失败，请重试');
        statusQRCode.value = '二维码申请失败，请重试';
        qrCodeLeftTime.value = 0;
      }
      return;
    }
    if (isClosed || generation != _qrGeneration) return;
    if (res case Success(:final response)) {
      codeInfo.value = res;
      qrCodeTimer = Timer.periodic(const Duration(milliseconds: 1000), (t) {
        if (isClosed || generation != _qrGeneration) {
          t.cancel();
          return;
        }
        final left = 180 - t.tick;
        if (left <= 0) {
          t.cancel();
          _qrGeneration++;
          statusQRCode.value = '二维码已过期，请刷新';
          qrCodeLeftTime.value = 0;
          return;
        }
        qrCodeLeftTime.value = left;
        if (_isReq || tabController.index != 2) return;

        _isReq = true;
        _session
            .pollQr(response.authCode)
            .then((value) async {
              if (isClosed || generation != _qrGeneration) return;
              if (value.isSuccess) {
                t.cancel();
                statusQRCode.value = '扫码成功';
                await setAccount(
                  value.data,
                  value.data['cookie_info']['cookies'],
                );
                if (!isClosed && generation == _qrGeneration) Get.back();
              } else if (value.code == 86038) {
                t.cancel();
                qrCodeLeftTime.value = 0;
              } else {
                statusQRCode.value = value.message;
                if (value.code == null) {
                  t.cancel();
                  qrCodeLeftTime.value = 0;
                }
              }
            })
            .catchError((Object error, StackTrace stackTrace) {
              if (!isClosed && generation == _qrGeneration) {
                statusQRCode.value = '二维码状态查询失败，请重试';
                qrCodeLeftTime.value = 0;
                t.cancel();
              }
            })
            .whenComplete(() {
              if (generation == _qrGeneration) _isReq = false;
            });
      });
    } else {
      codeInfo.value = res;
      qrCodeLeftTime.value = 0;
    }
  }

  void _handleTabChange() {
    if (_lastTabIndex == tabController.index) return;
    _lastTabIndex = tabController.index;
    if (tabController.index != 2) {
      qrCodeTimer?.cancel();
      _qrGeneration++;
      _isReq = false;
      return;
    }
    if (qrCodeTimer == null || !qrCodeTimer!.isActive) {
      refreshQRCode();
    }
  }

  // 申请极验验证码
  Future<void> getCaptcha(
    String geeGt,
    String geeChallenge,
    FutureOr<void> Function() onSuccess,
  ) async {
    final res = await GeetestWebviewDialog.geetest(geeGt, geeChallenge);
    if (!isClosed && res != null) {
      captchaData
        ..validate = res['geetest_validate']
        ..seccode = res['geetest_seccode']
        ..geetest = GeetestData(
          challenge: res['geetest_challenge'],
          gt: geeGt,
        );
      SmartDialog.showToast('验证成功');
      await onSuccess();
    }
  }

  bool _cookieLoginPending = false;

  Future<void> loginByCookie() async {
    if (isClosed || _cookieLoginPending) return;
    final input = cookieTextController.text;
    bool isCurrent() => !isClosed && cookieTextController.text == input;
    _cookieLoginPending = true;
    try {
      final result = await _session.loginWithCookie(
        input,
        isCurrent: isCurrent,
      );
      if (!isCurrent() || result == null) return;
      if (!result.isSuccess) {
        unawaited(result.toast());
        return;
      }
      if (!_session.mainIsLoggedIn) await showAccountSwitchDialog(Get.context!);
      if (!isCurrent()) return;
      SmartDialog.showToast('登录成功');
      Get.back();
    } finally {
      _cookieLoginPending = false;
    }
  }

  // app端密码登录
  Future<void> loginByPassword() async {
    if (isClosed) return;
    final generation = ++_passwordGeneration;
    final username = usernameTextController.text;
    final password = passwordTextController.text;
    bool isCurrent() =>
        !isClosed &&
        generation == _passwordGeneration &&
        usernameTextController.text == username &&
        passwordTextController.text == password;
    if (username.isEmpty || password.isEmpty) {
      SmartDialog.showToast('用户名或密码不能为空');
      return;
    }
    final res = await _session.submitPassword(
      username: username,
      password: password,
      captcha: captchaData,
      isCurrent: isCurrent,
    );
    if (!isCurrent() || res == null) return;
    if (res.isSuccess) {
      final data = res.data;
      if (data['status'] == 2) {
        SmartDialog.showToast(data['message']);
        final url = data['url'];
        final currentUri = url is String ? Uri.tryParse(url) : null;
        if (currentUri == null ||
            ['tmp_token', 'request_id', 'source'].any(
              (name) => currentUri.queryParameters[name]?.isNotEmpty != true,
            )) {
          SmartDialog.showToast('验证信息不完整，请重试或使用其他登录方式');
          return;
        }
        final safeCenterRes = await _session.getRiskAccount(currentUri);
        if (!isCurrent()) return;
        //{"code":0,"message":"0","ttl":1,"data":{"account_info":{"hide_tel":"111*****111","hide_mail":"aaa*****aaaa.aaa","bind_mail":true,"bind_tel":true,"tel_verify":true,"mail_verify":true,"unneeded_check":false,"bind_safe_question":false,"mid":1111111},"member_info":{"nickname":"xxxxxxx","face":"https://i0.hdslb.com/bfs/face/xxxxxxx.jpg","realname_status":false},"sns_info":{"bind_google":false,"bind_fb":false,"bind_apple":false,"bind_qq":true,"bind_weibo":true,"bind_wechat":false},"account_safe":{"score":80}}}
        if (!safeCenterRes.isSuccess) {
          SmartDialog.showToast(
            "获取安全验证信息失败，请尝试其它登录方式\n"
            "(${safeCenterRes.code}) ${safeCenterRes.message}",
          );
          return;
        }
        Map<String, String> accountInfo = {
          "hindTel":
              safeCenterRes.data['account_info']["hide_tel"]?.toString() ??
              '未能获取手机号',
          "hindMail":
              safeCenterRes.data['account_info']["hide_mail"]?.toString() ??
              '未能获取邮箱',
        };
        if (safeCenterRes.data['account_info']['tel_verify'] != true) {
          SmartDialog.showToast("当前账号未支持手机号验证，请尝试其它登录方式");
          return;
        }

        TextEditingController textFieldController = TextEditingController();
        String captchaKey = '';
        showDialog(
          context: Get.context!,
          builder: (context) => AlertDialog(
            titlePadding: const EdgeInsets.only(
              left: 16,
              top: 18,
              right: 16,
              bottom: 12,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            title: const Text(
              "本次登录需要验证您的手机号",
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  accountInfo['hindTel'] ?? '未能获取手机号',
                  style: const TextStyle(fontSize: 18),
                ),
                // 带有清空按钮的输入框
                TextField(
                  style: const TextStyle(fontSize: 15),
                  controller: textFieldController,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: "请输入短信验证码",
                    hintStyle: const TextStyle(fontSize: 15),
                    suffixIcon: iconButton(
                      icon: const Icon(Icons.clear),
                      size: 32,
                      onPressed: textFieldController.clear,
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      maxHeight: 32,
                      maxWidth: 32,
                    ),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text("发送验证码"),
                onPressed: () async {
                  final preCaptureRes = await _session.requestCaptcha();
                  if (!isCurrent() || !context.mounted) return;
                  if (!preCaptureRes.isSuccess) {
                    SmartDialog.showToast(
                      "获取验证码失败，请尝试其它登录方式\n"
                      "(${preCaptureRes.code}) ${preCaptureRes.message}",
                    );
                    return;
                  }
                  String geeGt = preCaptureRes.data['gee_gt'];
                  String geeChallenge = preCaptureRes.data['gee_challenge'];
                  captchaData.token = preCaptureRes.data['recaptcha_token'];
                  if (!isGeeArgumentValid(geeGt, geeChallenge)) {
                    SmartDialog.showToast(
                      "获取极验参数为空，请尝试其它登录方式\n"
                      "(${preCaptureRes.code}) ${preCaptureRes.message}",
                    );
                    return;
                  }

                  getCaptcha(
                    geeGt,
                    geeChallenge,
                    () async {
                      if (!isCurrent() || !context.mounted) return;
                      final safeCenterSendSmsCodeRes = await _session
                          .requestRiskSms(
                            uri: currentUri,
                            challenge: geeChallenge,
                            captcha: captchaData,
                          );
                      if (!isCurrent() || !context.mounted) return;
                      if (!safeCenterSendSmsCodeRes.isSuccess) {
                        SmartDialog.showToast(
                          "发送短信验证码失败，请尝试其它登录方式\n"
                          "(${safeCenterSendSmsCodeRes.code}) ${safeCenterSendSmsCodeRes.message}",
                        );
                        return;
                      }
                      SmartDialog.showToast("短信验证码已发送，请查收");
                      captchaKey = safeCenterSendSmsCodeRes.data['captcha_key'];
                    },
                  );
                },
              ),
              TextButton(
                onPressed: Get.back,
                child: Text(
                  "取消",
                  style: TextStyle(color: ThemeUtils.theme.colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () async {
                  String? code = textFieldController.text;
                  if (code.isEmpty) {
                    SmartDialog.showToast("请输入短信验证码");
                    return;
                  }
                  final safeCenterSmsVerifyRes = await _session.verifyRiskSms(
                    uri: currentUri,
                    code: code,
                    captchaKey: captchaKey,
                  );
                  if (!isCurrent() || !context.mounted) return;
                  if (!safeCenterSmsVerifyRes.isSuccess) {
                    SmartDialog.showToast(
                      "验证短信验证码失败，请尝试其它登录方式\n"
                      "(${safeCenterSmsVerifyRes.code}) ${safeCenterSmsVerifyRes.message}",
                    );
                    return;
                  }
                  SmartDialog.showToast("验证成功，正在登录");
                  final oauth2AccessTokenRes = await _session.exchangeRiskCode(
                    safeCenterSmsVerifyRes.data['code'],
                  );
                  if (!isCurrent() || !context.mounted) return;
                  if (!oauth2AccessTokenRes.isSuccess) {
                    SmartDialog.showToast(
                      "登录失败，请尝试其它登录方式\n"
                      "(${oauth2AccessTokenRes.code}) ${oauth2AccessTokenRes.message}",
                    );
                    return;
                  }
                  final data = oauth2AccessTokenRes.data;
                  if (data['token_info'] == null ||
                      data['cookie_info'] == null) {
                    SmartDialog.showToast(
                      '登录异常，接口未返回身份信息，可能是因为账号风控，请尝试其它登录方式。\n${oauth2AccessTokenRes.message}',
                    );
                    return;
                  }
                  SmartDialog.showToast('正在保存身份信息');
                  await setAccount(
                    data['token_info'],
                    data['cookie_info']['cookies'],
                  );
                  if (isCurrent() &&
                      context.mounted &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Get
                      ..back()
                      ..back();
                  }
                },
                child: const Text("确认"),
              ),
            ],
          ),
        ).whenComplete(textFieldController.dispose);

        return;
      }
      if (data['token_info'] == null || data['cookie_info'] == null) {
        SmartDialog.showToast(
          '登录异常，接口未返回身份信息，可能是因为账号风控，请尝试其它登录方式。\n${res.message}',
        );
        return;
      }
      SmartDialog.showToast('正在保存身份信息');
      await setAccount(data['token_info'], data['cookie_info']['cookies']);
      if (isCurrent()) Get.back();
    } else {
      // handle login result
      switch (res.code) {
        case 0:
          // login success
          break;
        case -105:
          final captureUrl = res.data['url'];
          final captureUri = captureUrl is String
              ? Uri.tryParse(captureUrl)
              : null;
          captchaData.token = captureUri?.queryParameters['recaptcha_token'];
          final geeGt = captureUri?.queryParameters['gee_gt'];
          final geeChallenge = captureUri?.queryParameters['gee_challenge'];
          if (!isGeeArgumentValid(geeGt, geeChallenge)) {
            SmartDialog.showToast('验证信息不完整，请重试或使用其他登录方式');
            return;
          }
          await getCaptcha(geeGt!, geeChallenge!, () async {
            if (isCurrent()) await loginByPassword();
          });
          break;
        default:
          SmartDialog.showToast(res.message);
          // login failed
          break;
      }
    }
  }

  // 短信验证码登录
  Future<void> loginBySmsCode() async {
    if (isClosed) return;
    final generation = ++_smsLoginGeneration;
    final tel = telTextController.text;
    final code = smsCodeTextController.text;
    final key = captchaKey;
    final country = selectedCountryCodeId.countryId;
    bool isCurrent() =>
        !isClosed &&
        generation == _smsLoginGeneration &&
        telTextController.text == tel &&
        smsCodeTextController.text == code &&
        captchaKey == key &&
        selectedCountryCodeId.countryId == country;
    if (tel.isEmpty) {
      SmartDialog.showToast('手机号不能为空');
      return;
    }
    if (key.isEmpty ||
        (_smsRecipient != null &&
            _smsRecipient != (tel: tel, country: country))) {
      SmartDialog.showToast('请先点击获取验证码');
      return;
    }
    if (code.isEmpty) {
      SmartDialog.showToast('验证码不能为空');
      return;
    }
    if (DateTime.now().millisecondsSinceEpoch - smsSendTimestamp >
        1000 * 60 * 5) {
      SmartDialog.showToast('验证码已过期，请重新获取');
      return;
    }
    final res = await _session.submitSms(
      tel: tel,
      code: code,
      captchaKey: key,
      cid: country,
      isCurrent: isCurrent,
    );
    if (!isCurrent() || res == null) return;
    if (res.isSuccess) {
      SmartDialog.showToast('登录成功');
      final data = res.data;
      await setAccount(data['token_info'], data['cookie_info']['cookies']);
      if (isCurrent()) Get.back();
    } else {
      SmartDialog.showToast(res.message);
    }
  }

  // app端验证码
  Future<void> sendSmsCode() async {
    if (isClosed || smsSending.value || smsSendCooldown.value > 0) return;
    smsSending.value = true;
    final tel = telTextController.text;
    final country = selectedCountryCodeId.countryId;
    bool isCurrent() =>
        !isClosed &&
        telTextController.text == tel &&
        selectedCountryCodeId.countryId == country;
    try {
      await _sendSmsCode(tel, country, isCurrent);
    } catch (_) {
      if (isCurrent()) SmartDialog.showToast('发送验证码失败，请重试');
    } finally {
      if (!isClosed) smsSending.value = false;
    }
  }

  Future<void> _sendSmsCode(
    String tel,
    Object country,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    if (tel.isEmpty) {
      SmartDialog.showToast('手机号不能为空');
      return;
    }
    final res = await _session.requestSms(
      tel: tel,
      cid: country,
      captcha: captchaData,
    );
    if (!isCurrent()) return;
    if (res.isSuccess) {
      SmartDialog.showToast('发送成功');
      smsSendTimestamp = DateTime.now().millisecondsSinceEpoch;
      smsSendCooldown.value = 60;
      captchaKey = res.data['captcha_key'];
      _smsRecipient = (tel: tel, country: country);
      smsSendCooldownTimer?.cancel();
      smsSendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        smsSendCooldown.value = 60 - timer.tick;
        if (smsSendCooldown.value <= 0) {
          timer.cancel();
          smsSendCooldown.value = 0;
        }
      });
    } else {
      // handle login result
      switch (res.code) {
        case 0:
        case -105:
          String? captureUrl = res.data['recaptcha_url'];
          String? geeGt;
          String? geeChallenge;
          if (captureUrl != null && captureUrl.isNotEmpty) {
            Uri captureUri = Uri.parse(captureUrl);
            captchaData.token = captureUri.queryParameters['recaptcha_token'];
            geeGt = captureUri.queryParameters['gee_gt'];
            geeChallenge = captureUri.queryParameters['gee_challenge'];
          }

          if (!isGeeArgumentValid(geeGt, geeChallenge)) {
            logger.w(
              '验证信息错误：${res.message}，尝试另一个验证码接口',
            );
            final preCaptureRes = await _session.requestCaptcha();
            if (!isCurrent()) return;
            if (!preCaptureRes.isSuccess) {
              SmartDialog.showToast(
                "获取验证码失败，请尝试其它登录方式\n"
                "(${preCaptureRes.code}) ${preCaptureRes.message}",
              );
              return;
            }
            geeGt = preCaptureRes.data['gee_gt'];
            geeChallenge = preCaptureRes.data['gee_challenge'];
            captchaData.token = preCaptureRes.data['recaptcha_token'];
          }

          if (!isGeeArgumentValid(geeGt, geeChallenge)) {
            SmartDialog.showToast("获取验证码失败，请尝试其它登录方式\n");
            return;
          }

          await getCaptcha(geeGt!, geeChallenge!, () {
            return _sendSmsCode(tel, country, isCurrent);
          });
          break;
        default:
          SmartDialog.showToast(res.message);
          break;
      }
    }
  }

  bool isGeeArgumentValid(String? geeGt, String? geeChallenge) {
    return geeGt?.isNotEmpty == true &&
        geeChallenge?.isNotEmpty == true &&
        captchaData.token?.isNotEmpty == true;
  }

  Future<void> setAccount(Map tokenInfo, List cookieInfo) async {
    await _session.loginWithAppCredentials(tokenInfo, cookieInfo);
    if (isClosed) return;
    if (_session.mainIsLoggedIn) {
      SmartDialog.showToast('登录成功');
    } else {
      SmartDialog.showToast('登录成功, 请先设置账号模式');
      await showAccountSwitchDialog(Get.context!);
    }
  }
}
