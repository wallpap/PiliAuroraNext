import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/messaging/conversation.dart';
import 'package:pili_aurora_next/services/messaging/message_models.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';

import 'messaging_fixtures.dart';

void main() {
  late MessagingSession session;
  late FakeConversationAdapter adapter;
  late Conversation chat;

  setUp(() {
    session = sessionFixture();
    adapter = FakeConversationAdapter();
    chat = Conversation(
      session: session,
      target: const ConversationTarget(talkerId: 456),
      adapter: adapter,
    );
  });
  tearDown(() {
    chat.dispose();
    session.dispose();
  });

  test('发送成功后的刷新应查询发送后的记录', () async {
    final initial = chat.open();
    expect((await chat.sendText('new message')).isSuccess, isTrue);
    final afterSend = chat.refresh(retryFailedAcknowledgement: false);
    expect(adapter.latestRequests.length, 2, reason: '发送前的查询不能保证包含已发送的新消息');
    adapter.latestRequests.first.complete(Success(page([10])));
    adapter.latestRequests.last.complete(Success(page([11, 10])));
    await initial;
    await afterSend;
    expect(chat.snapshot.messages.first.sequence, 11);
  });

  test('历史分页应保留最新页使用的表情映射', () async {
    final initial = chat.open();
    adapter.latestRequests.single.complete(
      Success(
        page(
          [10],
          emotions: const [
            EmotionSticker(text: '[new]', url: 'new.png', size: 22),
          ],
        ),
      ),
    );
    await initial;
    final older = chat.loadOlder();
    adapter.olderRequests.single.complete(
      Success(
        page(
          [9],
          hasOlder: false,
          emotions: const [
            EmotionSticker(text: '[old]', url: 'old.png', size: 22),
          ],
        ),
      ),
    );
    await older;
    expect(chat.snapshot.messages.length, 2);
    expect(
      chat.snapshot.emotions.map((item) => item.text),
      containsAll(['[new]', '[old]']),
    );
  });

  test('发送失败和网络未知均释放锁，允许下一次发送', () async {
    adapter.sendRequest = () async => const Error('失败');
    expect((await chat.sendText('first')).status, OperationStatus.failure);
    expect(chat.snapshot.isSending, isFalse);
    adapter.sendRequest = () async => throw DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.receiveTimeout,
    );
    expect((await chat.sendText('second')).status, OperationStatus.unknown);
    expect(chat.snapshot.isSending, isFalse);
    adapter.latestRequests.single.complete(Success(page([3])));
    await settle();
    adapter.sendRequest = () async => const Success(null);
    expect((await chat.sendText('third')).isSuccess, isTrue);
  });

  test('刷新使旧历史页失效，消息按稳定 ID 去重', () async {
    final initial = chat.open();
    adapter.latestRequests[0].complete(Success(page([10, 9])));
    await initial;
    final older = chat.loadOlder();
    final refresh = chat.refresh();
    adapter.latestRequests[1].complete(Success(page([11, 10])));
    await refresh;
    adapter.olderRequests.single.complete(Success(page([9, 8])));
    await older;
    expect(chat.snapshot.messages.map((m) => m.sequence), [11, 10, 9]);
  });

  test('历史加载不 ACK，渲染水位单调且手动刷新可重试失败 ACK', () async {
    final initial = chat.open();
    adapter.latestRequests.single.complete(Success(page([10, 9])));
    await initial;
    expect(adapter.acknowledgements, isEmpty);
    adapter.ackResult = const Error('失败');
    chat.markRendered(message(10));
    await settle();
    chat.markRendered(message(9));
    await settle();
    expect(adapter.acknowledgements, [10]);
    adapter.ackResult = const Success(null);
    final refresh = chat.refresh();
    adapter.latestRequests[1].complete(Success(page([10, 9])));
    await refresh;
    await settle();
    expect(adapter.acknowledgements, [10, 10]);
    expect(chat.snapshot.acknowledgedSequence, 10);
  });

  test('撤回遇到在途刷新仍按 ID 保留撤回状态', () async {
    final initial = chat.open();
    adapter.latestRequests.single.complete(Success(page([10, 9])));
    await initial;
    final refresh = chat.refresh();
    await chat.recall(message(9));
    adapter.latestRequests[1].complete(Success(page([11, 10, 9])));
    await refresh;
    expect(
      chat.snapshot.messages.singleWhere((m) => m.id == '9').recalled,
      isTrue,
    );
  });

  test('共享租约合并会话请求，最后释放后旧会话不再读写', () async {
    final cache = ConversationCache(
      session: session,
      adapter: adapter,
      maximumEntries: 1,
    );
    addTearDown(cache.dispose);
    const target = ConversationTarget(talkerId: 1);
    final first = cache.acquire(target);
    final other = cache.acquire(const ConversationTarget(talkerId: 2));
    final shared = cache.acquire(target);
    final firstRead = first.conversation.open();
    final sharedRead = shared.conversation.open();
    expect(adapter.latestRequests, hasLength(1));
    adapter.latestRequests.single.complete(Success(page([10])));
    await Future.wait([firstRead, sharedRead]);
    expect(first.conversation.snapshot.messages.single.sequence, 10);
    expect(shared.conversation.snapshot.messages.single.sequence, 10);

    first.release();
    final refresh = shared.conversation.refresh();
    expect(adapter.latestRequests, hasLength(2));
    shared.release();
    adapter.latestRequests.last.complete(Success(page([11, 10])));
    await refresh;
    await shared.conversation.open();
    expect(adapter.latestRequests, hasLength(2));

    final reopened = cache.acquire(target);
    expect(reopened.conversation.snapshot.messages, isEmpty);
    final read = reopened.conversation.open();
    expect(adapter.latestRequests, hasLength(3));
    adapter.latestRequests.last.complete(Success(page([12])));
    await read;
    expect(reopened.conversation.snapshot.messages.single.sequence, 12);
    reopened.release();
    other.release();
  });

  test('结构化内容递归不可变且不共享输入集合', () {
    final nested = <String, Object?>{
      'items': <Object?>['one'],
    };
    final content = StructuredMessageContent(MessageContentKind.tip, nested);
    (nested['items'] as List).add('two');
    expect(content.payload['items'], ['one']);
    expect(
      () => (content.payload['items'] as List).add('three'),
      throwsUnsupportedError,
    );
  });
}
