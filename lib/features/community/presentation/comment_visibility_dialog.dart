import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/community/application/comments/comment_visibility.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/common/feedback/clipboard_actions.dart';
import 'package:get/route_manager.dart' show Get, GetNavigation, GetPageRoute;
import 'package:material_ui/material_ui.dart';

/// 自动检查在发布页关闭后交付给原评论页；离开来源后不再交付迟到结果。
final class _ReplyCheck with RouteAware {
  _ReplyCheck(Route<dynamic>? route, this.ownerIsCurrent)
    : route = route ?? Get.routing.route {
    if (this.route case final GetPageRoute route) {
      routeObserver.subscribe(this, route);
    }
  }

  final Route<dynamic>? route;
  final bool Function()? ownerIsCurrent;
  final owner = AccountScope.capture();
  bool _cancelled = false;
  bool ownsDialog = false;

  bool get isValid =>
      !_cancelled &&
      owner.isCurrent &&
      (ownerIsCurrent?.call() ?? true) &&
      (route?.isActive ?? true) &&
      Get.context?.mounted == true;

  bool get isCurrent => isValid && (route?.isCurrent ?? true);

  @override
  void didPushNext() => _cancelled = true;

  @override
  void didPop() => _cancelled = true;

  void dispose() {
    _cancelled = true;
    routeObserver.unsubscribe(this);
  }
}

Future<void> checkReplyVisibility({
  required CommentReply replyInfo,
  required bool biliSendCommAntifraud,
  required Object sourceId,
  required bool isManual,
  Route<dynamic>? sourceRoute,
  bool Function()? ownerIsCurrent,
}) async {
  final check = _ReplyCheck(sourceRoute, ownerIsCurrent);
  final oid = replyInfo.oid.toInt();
  final type = replyInfo.type.toInt();
  final id = replyInfo.id.toInt();
  final message = replyInfo.content.message;

  void showReplyCheckResult(String message, {bool isBan = false}) {
    if (!check.isCurrent) return;
    final dialog = showDialog<void>(
      context: Get.context!,
      barrierDismissible: isManual,
      builder: (context) {
        final dialogRoute = ModalRoute.of(context);
        final navigator = Navigator.of(context);
        final colorScheme = ColorScheme.of(context);
        final color = isBan ? colorScheme.error : colorScheme.primary;
        final actions = [
          if (isBan)
            TextButton(
              onPressed: () {
                if (dialogRoute?.isCurrent != true) return;
                final canAppeal = check.isValid;
                navigator.pop();
                if (!canAppeal) return;
                String? uri;
                switch (type) {
                  case 1:
                    uri = IdUtils.av2bv(oid);
                  case 17:
                    uri = 'https://www.bilibili.com/opus/$oid';
                }
                if (uri != null) {
                  copyText(uri);
                }
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
              onPressed: () {
                if (dialogRoute?.isCurrent == true) navigator.pop();
              },
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
                  child: isBan
                      ? Icon(
                          size: 22,
                          color: color,
                          Icons.highlight_off_outlined,
                        )
                      : Icon(
                          size: 22,
                          color: color,
                          Icons.check_circle_outline_rounded,
                        ),
                ),
                TextSpan(
                  text: ' 评论检查结果',
                  style: TextStyle(color: color),
                ),
              ],
            ),
          ),
          content: SelectionText(message),
          actions: actions.isEmpty ? null : actions,
        );
      },
    );
    check.ownsDialog = true;
    // Future 表示查询已交付；弹窗自己的完成负责释放路由观察者。
    unawaited(
      dialog.then(
        (_) => check.dispose(),
        onError: (Object error, StackTrace stackTrace) {
          check.dispose();
          logger.w(
            '评论检查弹窗失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        },
      ),
    );
  }

  try {
    if (!check.isValid) return;
    if (Platform.isAndroid && biliSendCommAntifraud) {
      CommentVisibilityCheck.launchAndroidAssistant(
        check.owner.account,
        replyInfo,
        sourceId,
      );
      return;
    }
    if (!isManual) await Future<void>.delayed(const Duration(seconds: 8));
    if (!check.isCurrent) return;
    final result = await CommentVisibilityCheck.inspect(
      check.owner.account,
      replyInfo,
      isCurrent: () => check.isCurrent,
    );
    if (!check.isCurrent) return;
    if (result case Error error) {
      await error.toast();
      return;
    }
    switch (result?.dataOrNull) {
      case CommentVisibility.public:
        showReplyCheckResult('无账号状态下找到了你的评论，评论正常！\n\n你的评论：$message');
      case CommentVisibility.directLinkOnly:
        showReplyCheckResult(
          isManual
              ? '无账号状态下找到了你的评论，评论正常！\n\n你的评论：$message'
              : '''
你评论状态有点可疑，虽然无账号翻找评论区获取不到你的评论，但是无账号可通过
https://api.bilibili.com/x/v2/reply/reply?oid=$oid&pn=1&ps=20&root=$id&type=$type
获取你的评论，疑似评论区被戒严或者这是你的视频。

你的评论：$message''',
        );
      case CommentVisibility.ownViewOnly:
        showReplyCheckResult(
          '你的评论被shadow ban（仅自己可见）！\n\n你的评论: $message',
          isBan: true,
        );
      case CommentVisibility.missing:
        showReplyCheckResult(
          replyInfo.root.toInt() == 0
              ? '无法找到你的评论。\n\n你的评论：$message'
              : '评论不可见: $message',
          isBan: true,
        );
      case null:
        break;
    }
  } catch (error, stackTrace) {
    final failure = Error.fromException(error, stackTrace);
    if (check.isCurrent) await failure.toast();
  } finally {
    if (!check.ownsDialog) check.dispose();
  }
}
