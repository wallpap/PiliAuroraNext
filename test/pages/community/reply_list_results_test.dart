import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/comments/comment_actions.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/features/member_space/application/member_moderation.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/comment_fixture.dart';
import '../../support/controlled_interceptor.dart';
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
    await GStorage.localCache.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
  });

  test('确认拉黑后仅更新命中的评论，分页回包也不会恢复它们', () async {
    const blockedMid = 42;
    ReplyInfo blocked(int id) => reply(id)..mid = Int64(blockedMid);
    final pending = Completer<LoadingState<Object>>();
    final fixture = CommentFixture()
      ..responses.addAll([
        Success(
          MainListReply(
            upTop: blocked(1),
            replies: [
              reply(2, children: [blocked(3), reply(4)])..count = Int64(2),
              reply(5),
              blocked(6),
            ],
            subjectControl: SubjectControl(count: Int64(100)),
            cursor: CursorReply(next: Int64.ONE),
          ),
        ),
        Success(
          DetailListReply(
            root: blocked(1)
              ..replies.addAll([blocked(7), reply(8)])
              ..count = Int64(2),
            cursor: CursorReply(isEnd: true),
          ),
        ),
        Success(
          DialogListReply(
            replies: [blocked(9), reply(10)],
            cursor: CursorReply(isEnd: true),
          ),
        ),
        Success(
          MainListReply(replies: [reply(11)], cursor: CursorReply(isEnd: true)),
        ),
        pending.future,
      ]);
    final container = commentContainer(fixture);
    final main = commentsProvider(commentQuery());
    final thread = commentsProvider(
      commentQuery(
        thread: (root: 1, reply: null, dialog: null, seedAuthor: blockedMid),
      ),
    );
    final dialog = commentsProvider(
      commentQuery(thread: (root: 1, reply: null, dialog: 1, seedAuthor: null)),
    );
    final unaffected = commentsProvider(commentQuery());
    var mainUpdates = 0;
    container
      ..listen(main, (_, _) => mainUpdates++)
      ..listen(thread, (_, _) {})
      ..listen(dialog, (_, _) {})
      ..listen(unaffected, (_, _) {});
    await flushComments();

    List<CommentReply> rows(CommentsState snapshot) => snapshot.loading.data;
    final old = container.read(main);
    final oldUnaffected = container.read(unaffected);
    final oldPreview = rows(old)[1];
    final untouchedReply = rows(old)[2];
    final untouchedChild = oldPreview.replies.last;
    final paging = container.read(main.notifier).loadMore();
    await flushComments();
    final beforeBlock = mainUpdates;
    final interceptor = ControlledInterceptor();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
    addTearDown(() async {
      Request.dio.interceptors.remove(interceptor);
      await interceptor.close();
    });

    final moderation = MemberModeration.capture();
    final failed = moderation.block(blockedMid);
    await interceptor.waitForRequests(1);
    expect(interceptor.requests.first.options.path, Api.relationMod);
    interceptor.requests.first.reply.complete({'code': -1, 'message': '失败'});
    expect((await failed).isSuccess, isFalse);
    expect(mainUpdates, beforeBlock);

    final success = moderation.block(blockedMid);
    await interceptor.waitForRequests(2);
    expect(mainUpdates, beforeBlock);
    interceptor.requests.last.reply.complete({'code': 0});
    expect((await success).isSuccess, isTrue);

    final updated = container.read(main);
    expect(mainUpdates, beforeBlock + 1);
    expect(updated.source, same(old.source));
    expect(updated.count, old.count);
    expect(updated.busy, isTrue);
    expect(rows(updated).map((row) => row.id.toInt()), [2, 5]);
    expect(rows(updated).first.replies.single, same(untouchedChild));
    expect(rows(updated).last, same(untouchedReply));
    expect(oldPreview.replies, hasLength(2));
    expect(container.read(thread).root, isNull);
    expect(rows(container.read(thread)).single.id, Int64(8));
    expect(rows(container.read(dialog)).single.id, Int64(10));
    expect(container.read(unaffected), same(oldUnaffected));
    expect(fixture.reads, hasLength(5));

    pending.complete(
      Success(
        MainListReply(
          replies: [
            blocked(12),
            reply(13, children: [blocked(14)])..mid = Int64(43),
          ],
          cursor: CursorReply(isEnd: true),
          subjectControl: SubjectControl(count: Int64(100)),
        ),
      ),
    );
    await paging;
    final result = rows(container.read(main));
    expect(result.map((row) => row.id.toInt()), [2, 5, 13]);
    expect(result.last.replies, isEmpty);
    expect(fixture.reads, hasLength(5));

    final report = CommentActions.report(
      Accounts.main,
      result.last,
      reason: 1,
      block: true,
    );
    await interceptor.waitForRequests(3);
    expect(interceptor.requests.last.options.path, Api.replyReport);
    interceptor.requests.last.reply.complete({'code': 0});
    expect((await report).isSuccess, isTrue);
    expect(rows(container.read(main)).map((row) => row.id.toInt()), [2, 5]);
    expect(fixture.reads, hasLength(5));
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
    final upMid = Int64(123);
    final root = reply(
      2,
      level: 1,
      children: [
        reply(4, level: 3),
        reply(3),
        reply(8, level: 2)..mid = upMid,
        reply(9, level: 1)..replyControl = ReplyControl(upReply: true),
      ],
    )..count = Int64(4);
    final fixture = CommentFixture()
      ..responses.addAll([
        Success(
          DetailListReply(
            root: root,
            subjectControl: SubjectControl(upMid: upMid),
            cursor: CursorReply(isEnd: true),
          ),
        ),
        Success(
          DetailListReply(root: reply(2), cursor: CursorReply(isEnd: true)),
        ),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(
      commentQuery(thread: (root: 2, reply: 3, dialog: null, seedAuthor: null)),
    );
    container.listen(provider, (_, _) {});
    final comments = container.read(provider.notifier);
    await flushComments();
    expect(fixture.reads.single.anchor, 3);
    final displayedRoot = container.read(provider).root!;
    expect(displayedRoot.id, root.id);
    expect(displayedRoot.replies.map((item) => item.id.toInt()), [4, 3, 8, 9]);
    expect(
      container.read(provider).loading.data.map((item) => item.id.toInt()),
      [3, 8, 9],
    );
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
      [6, 3, 5, 8, 9],
    );
    await comments.refresh();
    expect(fixture.reads.last.anchor, isNull);
  });

  test('对话列表按等级过滤，同时保留 UP 主评论和被 UP 主回复的评论', () async {
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 4);
    final upMid = Int64(123);
    final fixture = CommentFixture()
      ..responses.add(
        Success(
          DialogListReply(
            subjectControl: SubjectControl(upMid: upMid),
            replies: [
              reply(10, level: 3),
              reply(20),
              reply(30, level: 2)..mid = upMid,
              reply(40, level: 1)..replyControl = ReplyControl(upReply: true),
            ],
            cursor: CursorReply(isEnd: true),
          ),
        ),
      );
    final container = commentContainer(fixture);
    final provider = commentsProvider(
      commentQuery(thread: (root: 2, reply: null, dialog: 7, seedAuthor: null)),
    );
    container.listen(provider, (_, _) {});
    await flushComments();
    expect(fixture.reads.single.dialog, 7);
    expect(
      container.read(provider).loading.data.map((item) => item.id.toInt()),
      [20, 30, 40],
    );
  });
}
