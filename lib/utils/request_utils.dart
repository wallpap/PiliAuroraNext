import 'dart:async' show unawaited;

import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
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
