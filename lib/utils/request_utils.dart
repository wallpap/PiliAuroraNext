import 'dart:async' show FutureOr, unawaited;
import 'dart:math' show min;

import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/validate.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/login/gaia_result.dart';
import 'package:pili_aurora_next/models/remote/relation/data.dart';
import 'package:pili_aurora_next/pages/group_panel/view.dart';
import 'package:pili_aurora_next/pages/login/geetest/geetest_webview_dialog.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/navigation_request.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract final class RequestUtils {
  static Future<void> addToWatchLater({String? bvid, Object? aid}) async {
    final account = Accounts.main;
    final result = await LaterLibrary.legacy.add(
      bvid: bvid,
      aid: aid,
      account: account,
    );
    if (!identical(account, Accounts.main)) return;
    if (result.isSuccess) {
      SmartDialog.showToast('已添加到稍后再看');
    } else {
      result.toast();
    }
  }

  static Future<void> syncHistoryStatus() async {
    final account = Accounts.history;
    if (account.isLogin) await HistoryLibrary.legacy.status(account);
  }

  static Future<void> actionRelationMod({
    required BuildContext context,
    Account? account,
    required dynamic mid,
    required bool isFollow,
    required ValueChanged<int>? afterMod,
    RelationData? followStatus,
    bool Function()? isCurrent,
  }) async {
    final requestAccount = account ?? Accounts.main;
    bool current() =>
        context.mounted &&
        identical(requestAccount, Accounts.main) &&
        (isCurrent?.call() ?? true);
    if (mid == null || !current()) {
      return;
    }
    void notify(int attribute) {
      try {
        afterMod?.call(attribute);
      } catch (error, stackTrace) {
        logger.w(
          '关系已更新，本地回调失败',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      }
    }

    feedBack();
    if (!isFollow) {
      final res = await VideoHttp.relationMod(
        account: requestAccount,
        mid: mid,
        act: 1,
        reSrc: 11,
      );
      if (!current()) return;
      if (res.isSuccess) {
        SmartDialog.showToast('关注成功');
        notify(2);
      } else {
        res.toast();
      }
    } else {
      if (followStatus?.tag == null) {
        final res = await UserHttp.userRelation(mid, account: requestAccount);
        if (!current()) return;
        if (res case Success(:final response)) {
          followStatus = response;
        } else {
          res.toast();
          return;
        }
      }

      if (context.mounted && current()) {
        bool isSpecialFollowed = followStatus!.special == 1;
        String text = isSpecialFollowed ? '移除特别关注' : '加入特别关注';
        Future<void>? pendingAction;
        void runAction(Future<void> Function() action) {
          pendingAction ??= action();
        }

        await showDialog<void>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            clipBehavior: Clip.hardEdge,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              DialogOption(
                onPressed: () => runAction(() async {
                  Get.back();
                  if (!current()) return;
                  final res = await MemberHttp.specialAction(
                    account: requestAccount,
                    fid: mid,
                    isAdd: !isSpecialFollowed,
                  );
                  if (!current()) return;
                  if (res.isSuccess) {
                    SmartDialog.showToast('$text成功');
                    notify(isSpecialFollowed ? 2 : -10);
                  } else {
                    res.toast();
                  }
                }),
                child: Text(text, style: const TextStyle(fontSize: 14)),
              ),
              DialogOption(
                onPressed: () => runAction(() async {
                  Get.back();
                  if (!current()) return;
                  final result = await showModalBottomSheet<Set<int>>(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    constraints: BoxConstraints(
                      maxWidth: min(640, context.mediaQueryShortestSide),
                    ),
                    builder: (BuildContext context) {
                      final maxChildSize =
                          PlatformUtils.isMobile &&
                              !context.mediaQuerySize.isPortrait
                          ? 1.0
                          : 0.7;
                      return DraggableScrollableSheet(
                        minChildSize: 0,
                        maxChildSize: 1,
                        snap: true,
                        expand: false,
                        snapSizes: [maxChildSize],
                        initialChildSize: maxChildSize,
                        builder: (context, scrollController) {
                          return GroupPanel(
                            mid: mid,
                            account: requestAccount,
                            tags: followStatus!.tag,
                            scrollController: scrollController,
                          );
                        },
                      );
                    },
                  );
                  if (current() && result != null) {
                    followStatus!.tag = result.toList();
                    notify(result.contains(-10) ? -10 : 2);
                  }
                }),
                child: const Text('设置分组', style: TextStyle(fontSize: 14)),
              ),
              DialogOption(
                onPressed: () => runAction(() async {
                  Get.back();
                  if (!current()) return;
                  final res = await VideoHttp.relationMod(
                    account: requestAccount,
                    mid: mid,
                    act: 2,
                    reSrc: 11,
                  );
                  if (!current()) return;
                  if (res.isSuccess) {
                    SmartDialog.showToast('取消关注成功');
                    notify(0);
                  } else {
                    res.toast();
                  }
                }),
                child: const Text('取消关注', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        );
        await pendingAction;
      }
    }
  }

  static ReplyInfo replyCast(Map res) {
    Map? emote = res['content']['emote'];
    emote?.forEach((key, value) {
      value['size'] = value['meta']['size'];
    });
    return ReplyInfo.create()..mergeFromProto3Json(
      res
        ..['content'].remove('members')
        ..['id'] = res['rpid']
        ..['member']['name'] = res['member']['uname']
        ..['member']['face'] = res['member']['avatar']
        ..['member']['level'] = res['member']['level_info']['current_level']
        ..['member']['vipStatus'] = res['member']['vip']['vipStatus']
        ..['member']['vipType'] = res['member']['vip']['vipType']
        ..['member']['officialVerifyType'] =
            res['member']['official_verify']['type']
        ..['content']['emotes'] = emote,
      ignoreUnknownFields: true,
    );
  }

  static Future<void> checkCreatedDyn({
    dynamic id,
    String? dynText,
    bool isManual = false,
    Account? account,
  }) async {
    account ??= Accounts.main;
    bool isCurrent() =>
        identical(account, Accounts.main) && Get.context?.mounted == true;
    if (isManual || Pref.enableCreateDynAntifraud) {
      try {
        if (id != null) {
          if (!isManual) {
            await Future.pause(const Duration(seconds: 5));
          }
          if (!isCurrent()) return;
          final res = await DynamicDetails.legacy.checkPublicVisibility(id);
          if (!isCurrent()) return;
          if (res is Error) {
            SmartDialog.showToast('暂时无法确认动态可见性：$res');
            return;
          }
          final isSuccess = res.data;
          showDialog(
            context: Get.context!,
            barrierDismissible: isManual,
            builder: (context) {
              final colorScheme = ColorScheme.of(context);
              final color = isSuccess ? colorScheme.primary : colorScheme.error;
              final actions = [
                if (!isSuccess)
                  TextButton(
                    onPressed: () {
                      Get.back();
                      Utils.copyText('https://www.bilibili.com/opus/$id');
                      Get.toNamed(
                        '/webview',
                        parameters: {
                          'url':
                              'https://www.bilibili.com/h5/comment/appeal?${ThemeUtils.themeUrl(colorScheme.isDark)}',
                        },
                      );
                    },
                    child: const Text('申诉'),
                  ),
                if (!isManual)
                  TextButton(
                    onPressed: Get.back,
                    child: Text(
                      '关闭',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
              ];
              return AlertDialog(
                title: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: .middle,
                        child: isSuccess
                            ? Icon(
                                size: 22,
                                color: color,
                                Icons.check_circle_outline_rounded,
                              )
                            : Icon(
                                size: 22,
                                color: color,
                                Icons.highlight_off_outlined,
                              ),
                      ),
                      TextSpan(
                        text: ' 动态检查结果',
                        style: TextStyle(color: color),
                      ),
                    ],
                  ),
                ),
                content: SelectionText(
                  '${isSuccess ? '未登录状态下可以查看该动态。' : '未登录状态下无法查看该动态，请检查可见范围。'}${dynText != null ? ' \n\n动态内容: $dynText' : ''}',
                ),
                actions: actions.isEmpty ? null : actions,
              );
            },
          );
        }
      } catch (e, stackTrace) {
        logger.w('check dyn error: $e', error: e, stackTrace: stackTrace);
      }
    }
  }

  static Future<void> validate(
    String vVoucher,
    FutureOr<void> Function(String) onSuccess, {
    required Account account,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    final res = await ValidateHttp.gaiaVgateRegister(
      vVoucher,
      account: account,
    );
    if (!isCurrent()) return;
    if (!res.isSuccess) {
      if (res is UnknownResult) {
        SmartDialog.showToast('验证响应未能确认，请重新打开验证');
      } else {
        res.toast();
      }
      return;
    }

    final registration = res.data;
    final Map<String, dynamic>? json;
    try {
      json = await GeetestWebviewDialog.geetest(
        registration.gt,
        registration.challenge,
      );
    } catch (error, stackTrace) {
      logger.w('打开风控验证失败', error: error.runtimeType, stackTrace: stackTrace);
      if (isCurrent()) SmartDialog.showToast('无法打开验证，请重试');
      return;
    }
    if (!isCurrent() || json == null) return;
    final challenge = json['geetest_challenge'];
    final seccode = json['geetest_seccode'];
    final validate = json['geetest_validate'];
    if (challenge is! String ||
        seccode is! String ||
        validate is! String ||
        [challenge, seccode, validate].any((value) => value.trim().isEmpty)) {
      SmartDialog.showToast('验证结果不完整，请重新打开验证');
      return;
    }
    final result = await ValidateHttp.gaiaVgateValidate(
      account: account,
      challenge: challenge,
      seccode: seccode,
      token: registration.token,
      validate: validate,
    );
    if (!isCurrent()) return;
    switch (result) {
      case Success(response: GaiaVerified(:final riskId)):
        await onSuccess(riskId);
      case Success(response: GaiaRejected()):
        SmartDialog.showToast('验证未通过，请重试');
      case UnknownResult():
        SmartDialog.showToast('验证响应未能确认，请重新打开验证');
      case Error():
        result.toast();
      case Loading():
        break;
    }
  }

  static Future<void> showUserRealName(String mid) async {
    final request = NavigationRequest();
    final account = Accounts.main;
    bool current() => request.isCurrent && identical(account, Accounts.main);
    try {
      final res = await UserHttp.getUserRealName(mid, account: account);
      if (!current() || Get.context?.mounted != true) return;
      if (res case Success(:final response)) {
        final show = !response.name.isNullOrEmpty;
        final dialog = showDialog<void>(
          context: Get.context!,
          builder: (context) => AlertDialog(
            title: SelectionText(
              show ? response.name! : response.rejectPage?.title ?? '',
            ),
            content: show ? null : Text(response.rejectPage?.text ?? ''),
            actions: [
              TextButton(
                onPressed: () {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('关闭'),
              ),
            ],
          ),
        );
        unawaited(
          dialog.then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              logger.w(
                '实名信息弹窗失败',
                error: error.runtimeType,
                stackTrace: stackTrace,
              );
            },
          ),
        );
      } else {
        res.toast();
      }
    } catch (error, stackTrace) {
      logger.w('实名信息查询失败', error: error.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('实名信息查询失败，请重试');
    } finally {
      await request.close();
    }
  }
}
