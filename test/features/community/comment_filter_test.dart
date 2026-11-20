import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/domain/comment_filter.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';

void main() {
  test('保留阈值、硬核用户和未知资料，兼容 memberV2 与默认 Lv0', () {
    final replies = [
      ReplyInfo(id: Int64(1), member: Member()),
      ReplyInfo(
        id: Int64(2),
        member: Member(level: Int64(3)),
      ),
      ReplyInfo(
        id: Int64(3),
        member: Member(level: Int64(6)),
      ),
      ReplyInfo(
        id: Int64(4),
        member: Member(level: Int64(7)),
      ),
      ReplyInfo(id: Int64(5)),
      ReplyInfo(
        id: Int64(6),
        memberV2: MemberV2(
          basic: MemberV2_Basic(level: Int64(2)),
        ),
      ),
      ReplyInfo(
        id: Int64(7),
        memberV2: MemberV2(
          basic: MemberV2_Basic(level: Int64(3)),
        ),
      ),
    ].map(commentFromProtocol).toList();
    filterRepliesByLevel(replies, 3);
    expect(replies.map((reply) => reply.id.toInt()), [2, 3, 4, 5, 7]);
  });

  test('关闭过滤保留原对象和预览内容', () {
    final root = commentFromProtocol(
      ReplyInfo(
        member: Member(),
        replies: [ReplyInfo(member: Member())],
      ),
    );
    final replies = [root];
    filterRepliesByLevel(replies, 0);
    expect(replies.single, same(root));
    expect(root.replies, hasLength(1));
  });
}
