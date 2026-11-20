import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/comment_fixture.dart';
import '../../support/memory_box.dart';

LoginAccount account(String csrf) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
  null,
  null,
);
ReplyInfo reply(int id, {int level = 6, List<ReplyInfo>? children}) =>
    ReplyInfo(
      id: Int64(id),
      oid: Int64.ONE,
      type: Int64.ONE,
      replies: children,
      member: Member(level: Int64(level)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.localCache = MemoryBox();
  });
  setUp(() async {
    await GStorage.setting.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
  });

  test('按 ID 更新回显，重复回执和旧子项位置不改当前列表', () async {
    final fixture = CommentFixture()
      ..responses.add(
        Success(
          MainListReply(
            upTop: reply(1),
            replies: [
              reply(2, children: [reply(3)])..count = Int64.ONE,
            ],
            cursor: CursorReply(isEnd: true),
          ),
        ),
      );
    final container = commentContainer(fixture);
    final provider = commentsProvider(commentQuery());
    container.listen(provider, (_, _) {});
    final comments = container.read(provider.notifier);
    await flushComments();
    List<CommentReply> rows() => container.read(provider).loading.data;
    final old = rows().last;
    comments
      ..published(commentFromProtocol(reply(4)))
      ..published(commentFromProtocol(reply(4)));
    expect(rows().map((item) => item.id.toInt()), [1, 4, 2]);
    comments
      ..published(commentFromProtocol(reply(5)), parent: old)
      ..published(commentFromProtocol(reply(5)), parent: old);
    expect(rows().last.replies.map((item) => item.id.toInt()), [3, 5]);
    expect(rows().last.count, Int64(2));
    comments.remove(old, 0);
    expect(rows().last.replies, hasLength(2));
    comments.remove(rows().last, 1);
    expect(rows().last.replies.single.id.toInt(), 3);
    comments.remove(rows().last, null);
    expect(rows().map((item) => item.id.toInt()), [1, 4]);
    expect(container.read(provider).count, -1);
  });

  test('换同 UID 的凭据淘汰在途回复与旧编辑器，释放后不再查询', () async {
    final slow = Completer<LoadingState<MainListReply>>();
    final fixture = CommentFixture()
      ..responses.addAll([
        slow.future,
        Success(
          MainListReply(replies: [reply(10)], cursor: CursorReply(isEnd: true)),
        ),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(commentQuery());
    final subscription = container.listen(provider, (_, _) {});
    final comments = container.read(provider.notifier);
    final ownsEditor = comments.capture();
    await flushComments();
    Accounts.replaceCredentials(account('new'));
    await container.pump();
    await flushComments();
    slow.complete(Success(MainListReply(replies: [reply(9)])));
    await flushComments();
    expect(ownsEditor(), isFalse);
    expect(container.read(provider).loading.data.single.id.toInt(), 10);
    subscription.close();
    await container.pump();
    Accounts.replaceCredentials(account('closed'));
    await flushComments();
    expect(fixture.reads, hasLength(2));
  });

  test('楼中楼使用锚点首查，保留根评论、过滤等级和回显位置', () async {
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 4);
    final root = reply(2, children: [reply(4, level: 3), reply(3)])
      ..count = Int64(2);
    final fixture = CommentFixture()
      ..responses.addAll([
        Success(DetailListReply(root: root, cursor: CursorReply(isEnd: true))),
        Success(
          DetailListReply(root: reply(2), cursor: CursorReply(isEnd: true)),
        ),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(
      commentQuery(thread: (root: 2, reply: 3, dialog: null)),
    );
    container.listen(provider, (_, _) {});
    final comments = container.read(provider.notifier);
    await flushComments();
    expect(fixture.reads.single.anchor, 3);
    final displayedRoot = container.read(provider).root!;
    expect(displayedRoot.id, root.id);
    expect(displayedRoot.replies.map((item) => item.id.toInt()), [4, 3]);
    expect(container.read(provider).loading.data.single.id.toInt(), 3);
    comments
      ..published(
        commentFromProtocol(reply(5)),
        parent: commentFromProtocol(reply(3)),
      )
      ..published(
        commentFromProtocol(reply(5)),
        parent: commentFromProtocol(reply(3)),
      )
      ..published(
        commentFromProtocol(reply(6)),
        parent: commentFromProtocol(root),
      );
    expect(
      container.read(provider).loading.data.map((item) => item.id.toInt()),
      [6, 3, 5],
    );
    await comments.refresh();
    expect(fixture.reads.last.anchor, isNull);
  });

  test('对话协议的列表也按等级过滤', () async {
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 4);
    final fixture = CommentFixture()
      ..responses.add(
        Success(
          DialogListReply(
            replies: [reply(10, level: 3), reply(20)],
            cursor: CursorReply(isEnd: true),
          ),
        ),
      );
    final container = commentContainer(fixture);
    final provider = commentsProvider(
      commentQuery(thread: (root: 2, reply: null, dialog: 7)),
    );
    container.listen(provider, (_, _) {});
    await flushComments();
    expect(fixture.reads.single.dialog, 7);
    expect(container.read(provider).loading.data.single.id.toInt(), 20);
  });
}
