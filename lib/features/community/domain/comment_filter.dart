import 'package:pili_aurora_next/features/community/domain/comment.dart';

/// 仅扫描本页及保留评论的预览，不读取设置、不查询用户资料。
void filterRepliesByLevel(List<CommentReply> replies, int minimumLevel) {
  if (minimumLevel <= 0) return;
  replies.removeWhere((reply) {
    final level = reply.authorLevel;
    if (level != null && level >= 0 && level < minimumLevel) return true;
    filterRepliesByLevel(reply.replies, minimumLevel);
    return false;
  });
}
