import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';

List<CommentReply> filterRepliesByAuthor(
  List<CommentReply> replies,
  bool Function(CommentReply) isBlocked,
) {
  List<CommentReply>? filtered;
  for (var index = 0; index < replies.length; index++) {
    final reply = replies[index];
    if (isBlocked(reply)) {
      filtered ??= replies.sublist(0, index);
      continue;
    }
    final children = filterRepliesByAuthor(reply.replies, isBlocked);
    if (!identical(children, reply.replies)) {
      (filtered ??= replies.sublist(
        0,
        index,
      )).add(reply.copy(replies: children));
    } else {
      filtered?.add(reply);
    }
  }
  return filtered ?? replies;
}

/// 仅扫描本页及保留评论的预览，不读取设置、不查询用户资料。
void filterRepliesByLevel(
  List<CommentReply> replies,
  int minimumLevel,
  Int64? upMid,
) {
  if (minimumLevel <= 0) return;
  replies.removeWhere((reply) {
    final level = reply.authorLevel;
    if (level != null &&
        level >= 0 &&
        level < minimumLevel &&
        !reply.replyControl.upReply &&
        (upMid == Int64.ZERO || reply.mid != upMid)) {
      return true;
    }
    filterRepliesByLevel(reply.replies, minimumLevel, upMid);
    return false;
  });
}
