import 'dart:async' show unawaited;

import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';
import 'package:pili_aurora_next/utils/navigation_request.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract final class RequestUtils {
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
