import 'dart:math' show min;

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/features/following/application/follow_actions.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/relation/data.dart';
import 'package:pili_aurora_next/pages/group_panel/view.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';

Future<void> showFollowActions({
  required BuildContext context,
  Account? account,
  required Object? mid,
  required bool isFollow,
  required ValueChanged<int>? afterMod,
  RelationData? followStatus,
  bool Function()? isCurrent,
}) async {
  const actions = FollowActions();
  final requestAccount = account ?? actions.account;
  bool current() =>
      context.mounted &&
      actions.owns(requestAccount) &&
      (isCurrent?.call() ?? true);
  final target = switch (mid) {
    int value => value,
    String value => int.tryParse(value),
    _ => null,
  };
  if (target == null || !current()) {
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
    final res = await actions.setFollowing(requestAccount, target, true);
    if (!current()) return;
    if (res.isSuccess) {
      SmartDialog.showToast('关注成功');
      notify(2);
    } else {
      res.toast();
    }
  } else {
    if (followStatus?.tag == null) {
      final res = await actions.relation(requestAccount, target);
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
                final res = await actions.setSpecial(
                  requestAccount,
                  target,
                  !isSpecialFollowed,
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
                          mid: target,
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
                final res = await actions.setFollowing(
                  requestAccount,
                  target,
                  false,
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
