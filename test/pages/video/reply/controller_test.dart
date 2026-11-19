import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';

import '../../../support/comment_fixture.dart';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../../support/memory_box.dart';

ReplyInfo _reply(int id) => ReplyInfo(id: Int64(id));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
  });
  setUp(() => GStorage.setting.clear());

  ReplyInfo withLevel(int id, int level, [List<ReplyInfo>? replies]) =>
      ReplyInfo(
        id: Int64(id),
        member: Member(level: Int64(level)),
        replies: replies,
      );

  MainListReply page(List<ReplyInfo> replies, {bool end = false}) =>
      MainListReply(
        replies: replies,
        cursor: CursorReply(
          isEnd: end,
          next: replies.isEmpty ? Int64.ZERO : replies.last.id,
        ),
        subjectControl: SubjectControl(count: Int64(100)),
      );

  test('等级过滤补位保留后续页，置顶和楼中楼预览使用同一规则', () async {
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 4);
    final first = page([withLevel(1, 2)])..upTop = withLevel(9, 1);
    final fixture = CommentFixture()
      ..responses.addAll([
        Success(first),
        Success(
          page([
            withLevel(2, 4, [withLevel(3, 0), withLevel(4, 6)]),
          ], end: true),
        ),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(commentQuery());
    container.listen(provider, (_, _) {});
    await flushComments();
    final replies = container.read(provider).loading.dataOrNull!;
    expect(replies.map((r) => r.id.toInt()), [2]);
    expect(replies.single.replies.map((r) => r.id.toInt()), [4]);
    expect(
      container
              .read(provider)
              .loading
              .dataOrNull
              ?.firstOrNull
              ?.replyControl
              .isUpTop ??
          false,
      isFalse,
    );
    expect(fixture.reads.length, 2);
    expect(container.read(provider).count, 100);
    expect(!container.read(provider).hasMore, isTrue);
  });

  test('连续过滤最多请求五页，空列表仍可继续加载下一批', () async {
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 6);
    final fixture = CommentFixture()
      ..responses.addAll([
        for (var i = 1; i <= 5; i++) Success(page([withLevel(i, 1)])),
        Success(page([withLevel(6, 6)], end: true)),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(commentQuery());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await flushComments();
    expect(fixture.reads.length, 5);
    expect(container.read(provider).loading.dataOrNull, isEmpty);
    expect(!container.read(provider).hasMore, isFalse);
    expect(container.read(provider).hasMore, isTrue);
    await controller.loadMore(retry: true);
    expect(fixture.reads.length, 6);
    expect(container.read(provider).loading.dataOrNull!.single.id.toInt(), 6);
  });

  test('关闭过滤保留 Lv0，设置变更在刷新后重新加载', () async {
    final fixture = CommentFixture()
      ..responses.addAll([
        Success(page([withLevel(1, 0)], end: true)),
        Success(page([withLevel(1, 0), withLevel(2, 5)], end: true)),
      ]);
    final container = commentContainer(fixture);
    final provider = commentsProvider(commentQuery());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await flushComments();
    expect(container.read(provider).loading.dataOrNull!.single.id.toInt(), 1);
    await GStorage.setting.put(SettingBoxKey.minimumReplyUserLevel, 3);
    await controller.refresh();
    expect(container.read(provider).loading.dataOrNull!.single.id.toInt(), 2);
  });

  test(
    'pagination removes replies already shown and repeated in one page',
    () async {
      final fixture = CommentFixture()
        ..responses.addAll([
          Success(
            MainListReply(
              replies: [_reply(1), _reply(2)],
              subjectControl: SubjectControl(count: Int64(4)),
            ),
          ),
          Success(
            MainListReply(
              replies: [_reply(2), _reply(3), _reply(3)],
              subjectControl: SubjectControl(count: Int64(4)),
            ),
          ),
        ]);
      final container = commentContainer(fixture);
      final provider = commentsProvider(commentQuery());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);

      await flushComments();
      await controller.loadMore(retry: true);

      expect(
        container
            .read(provider)
            .loading
            .dataOrNull!
            .map(
              (reply) => reply.id.toInt(),
            ),
        [1, 2, 3],
      );
    },
  );
}
