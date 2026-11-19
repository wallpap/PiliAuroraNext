import 'package:fixnum/fixnum.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/controller.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/models/common/reply/reply_sort_type.dart';
import 'package:pili_aurora_next/http/loading_state.dart' show Error;
import 'package:pili_aurora_next/pages/common/publish/publish_route.dart';
import 'package:pili_aurora_next/pages/video/reply_new/view.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/reply_utils.dart';

/// 编辑器路由暂存当前页面的草稿，提交结果交回原评论目标。
class CommentInteractions {
  final _drafts =
      <({int oid, int type, int root, int parent}), List<RichTextItem>>{};
  Object? _account;

  void compose(
    BuildContext context,
    Comments comments,
    CommentsState state,
    Object sourceId,
    ReplyInfo? item, {
    int? oid,
    int? replyType,
    bool Function()? targetIsCurrent,
  }) {
    final ownsAccount = comments.capture();
    bool current() => ownsAccount() && (targetIsCurrent?.call() ?? true);
    if (!current()) return;
    final account = comments.accountIdentity;
    if (!identical(_account, account)) {
      _account = account;
      _drafts.clear();
    }
    if (state.loading case Error(:final errMsg, :final code)
        when errMsg != null && (code == 12061 || code == 12002)) {
      SmartDialog.showToast(errMsg);
      return;
    }
    final subject = state.subject;
    final text = subject?.rootText;
    if (subject?.inputDisable == true) {
      if (text != null && text.isNotEmpty) SmartDialog.showToast(text);
      return;
    }
    final route = ModalRoute.of(context);
    final hint = text != null && (text.contains('可发') || text.contains('可见'))
        ? text
        : null;
    final target = comments.query.target;
    final root = item == null || oid != null
        ? 0
        : (item.root != Int64.ZERO ? item.root : item.id).toInt();
    final key = (
      oid: oid ?? item?.oid.toInt() ?? target.oid,
      type: item?.type.toInt() ?? replyType ?? target.type,
      root: root,
      parent: item == null || oid != null ? 0 : item.id.toInt(),
    );
    Navigator.of(context, rootNavigator: true).push(
      PublishRoute(
        settings: RouteSettings(arguments: route?.settings.arguments),
        pageBuilder: (_, _, _) => ReplyPage(
          hint: hint,
          oid: key.oid,
          root: key.root,
          parent: key.parent,
          replyType: key.type,
          replyItem: item,
          items: _drafts[key],
          onSave: (draft) {
            if (!context.mounted || !current()) return;
            if (draft.isEmpty) {
              _drafts.remove(key);
            } else {
              _drafts[key] = List.of(draft);
            }
          },
          onSuccess: (reply) {
            if (!context.mounted || !current()) return;
            _drafts.remove(key);
            comments.published(reply, parent: item);
            if (reply != null && comments.checkCommentVisibility) {
              check(
                comments,
                sourceId,
                reply,
                isManual: false,
                sourceRoute: route,
                targetIsCurrent: current,
              );
            }
          },
        ),
      ),
    );
  }

  void check(
    Comments comments,
    Object sourceId,
    ReplyInfo item, {
    bool isManual = true,
    Route<dynamic>? sourceRoute,
    bool Function()? targetIsCurrent,
  }) => ReplyUtils.onCheckReply(
    replyInfo: item,
    biliSendCommAntifraud: comments.sendVisibilityCheck,
    sourceId: sourceId,
    isManual: isManual,
    sourceRoute: sourceRoute,
    ownerIsCurrent: targetIsCurrent ?? comments.capture(),
  );

  Future<void> togglePinned(
    BuildContext context,
    Comments comments,
    ReplyInfo item, {
    CommentTarget? target,
  }) async {
    final pinned = item.replyControl.isUpTop;
    final result = await comments.togglePinned(item, target: target);
    if (!context.mounted || result == null) return;
    if (result.isSuccess) {
      SmartDialog.showToast('${pinned ? '取消' : ''}置顶成功');
    } else {
      result.toast();
    }
  }

  void toggleSort(Comments comments, CommentsState state) {
    if (state.busy || state.sort == ReplySortType.select) return;
    feedBack();
    comments.toggleSort();
  }
}
