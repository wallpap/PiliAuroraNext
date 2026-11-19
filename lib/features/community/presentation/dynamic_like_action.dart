import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_actions.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';

Future<void> onLikeDynamic(
  BuildContext context,
  DynamicItemModel item,
  bool displayedStatus,
  VoidCallback onSuccess,
) async {
  final identity = AccountScope.capture();
  final account = identity.account;
  final id = item.idStr;
  final stat = item.modules.moduleStat?.like;
  final actions = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(dynamicsActionsProvider);
  final pending = actions.toggleLike(account, item, displayedStatus);
  if (pending == null) return;
  feedBack();
  final result = await pending;
  if (!context.mounted ||
      !identity.isCurrent ||
      id != item.idStr ||
      !identical(stat, item.modules.moduleStat?.like)) {
    return;
  }
  switch (result) {
    case Success(response: final liked):
      SmartDialog.showToast(liked ? '点赞成功' : '取消赞');
      onSuccess();
    case Error():
      result.toast();
    default:
      break;
  }
}
