import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/data/topic_repository.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  const repository = TopicRepository();
  final account = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '11', 'bili_jct': 'captured'}),
    null,
    null,
  );
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(requests.clear);
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('点赞凭据和 CSRF 来自捕获账号，写入关闭自动重试', () async {
    Accounts.accountMode[AccountType.main.index] = const NoAccount();
    final result = repository.like(account, '42', false);
    await interceptor.waitForRequests(1);
    final options = requests.single.options;
    expect(options.extra['account'], same(account));
    expect(options.extra['noRetry'], true);
    expect(options.data, containsPair('csrf', 'captured'));
    expect(options.data, containsPair('up_mid', 11));
    requests.single.reply.complete({'code': 0});
    expect(await result, isA<Success>());
  });

  test('话题搜索固定账号并保留偏移分页协议', () async {
    final result = repository.search(account, 'test', 2);
    await interceptor.waitForRequests(1);
    expect(requests.single.options.extra['account'], same(account));
    expect(requests.single.options.queryParameters['offset'], 20);
    requests.single.reply.complete({
      'code': 0,
      'data': {
        'topic_items': [],
        'page_info': {'has_more': false},
      },
    });
    expect((await result).data.hasMore, false);
  });

  test('话题游标重复时结束，详情保留无数据与协议损坏的区别', () async {
    final first = repository.feed(account, '42', 1, null);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete({
      'code': 0,
      'data': {
        'topic_card_list': {'has_more': true, 'offset': 'next', 'items': []},
      },
    });
    final page = (await first).data;
    expect(page.hasMore, true);
    final next = repository.feed(account, '42', 1, page.metadata);
    await interceptor.waitForRequests(2);
    expect(requests[1].options.queryParameters['offset'], 'next');
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'topic_card_list': {'has_more': true, 'offset': 'next', 'items': []},
      },
    });
    expect((await next).data.hasMore, false);
    final top = repository.top(account, '42');
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({'code': 0, 'data': {}});
    expect((await top).data, isNull);
    final malformed = repository.top(account, '42');
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({
      'code': 0,
      'data': {'top_details': {}},
    });
    expect(await malformed, isA<Error>());
  });
}
