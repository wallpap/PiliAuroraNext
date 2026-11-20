import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/curated_feed.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  LoginAccount account() => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '3', 'bili_jct': 'fixture'}),
    null,
    null,
  );
  Map<String, Object> catalog(int number) => {
    'code': 0,
    'data': {
      'list': [
        {'number': number, 'name': '期数$number'},
      ],
    },
  };
  Map<String, Object> detail(int number) => {
    'code': 0,
    'data': {
      'list': [],
      'config': {'name': '期数$number', 'media_id': number},
      'reminder': '说明$number',
    },
  };
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox({
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'fixture',
    });
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    container = ProviderContainer();
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    Accounts.accountMode[AccountType.recommend.index] = account();
  });
  tearDown(() => container.dispose());
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  test('目录解析失败可重试，等待详情完成后原子发布播放列表元数据', () async {
    final provider = weeklyFeedProvider((owner: Object(), number: null));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete({
      'code': 0,
      'data': {
        'list': [<String, dynamic>{}],
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).loading, isA<Error>());
    final retry = container.read(provider.notifier).onReload();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(catalog(2));
    await interceptor.waitForRequests(3);
    expect(container.read(provider).metadata, isNull);
    expect(
      requests[2].options.extra['account'],
      same(requests[1].options.extra['account']),
    );
    requests[2].reply.complete(detail(2));
    await retry;
    expect(container.read(provider).metadata?.number, 2);
    expect(container.read(provider).metadata?.config?.mediaId, 2);
    expect(container.read(provider).metadata?.reminder, '说明2');
    expect(container.read(provider).hasMore, isFalse);
  });
  test('刷新期间迟到的目录不启动详情；换凭据也停止旧账号后续步骤', () async {
    final provider = weeklyFeedProvider((owner: Object(), number: null));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    final refresh = container.read(provider.notifier).onRefresh();
    await interceptor.waitForRequests(2);
    requests[0].reply.complete(catalog(1));
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 2);
    final replacement = account();
    Accounts.replaceCredentials(replacement);
    container.read(provider);
    await interceptor.waitForRequests(3);
    requests[1].reply.complete(catalog(2));
    await refresh;
    expect(requests.length, 3);
    requests[2].reply.complete(catalog(3));
    await interceptor.waitForRequests(4);
    expect(requests[3].options.extra['account'], same(replacement));
    requests[3].reply.complete(detail(3));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).metadata?.number, 3);
  });
  test('离页后目录返回不启动详情', () async {
    final provider = weeklyFeedProvider((owner: Object(), number: null));
    final subscription = container.listen(provider, (_, _) {});
    container.read(provider);
    await interceptor.waitForRequests(1);
    subscription.close();
    await container.pump();
    requests[0].reply.complete(catalog(1));
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 1);
  });
  test('期数属于查询键，旧期详情不覆盖新期元数据', () async {
    final owner = Object();
    final first = weeklyFeedProvider((owner: owner, number: 1));
    final subscription = container.listen(first, (_, _) {});
    container.read(first);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(catalog(2));
    await interceptor.waitForRequests(2);
    subscription.close();
    final next = weeklyFeedProvider((owner: owner, number: 2));
    container
      ..listen(next, (_, _) {})
      ..read(next);
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(catalog(2));
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(detail(2));
    requests[1].reply.complete(detail(1));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(next).metadata?.config?.mediaId, 2);
  });
  test('入站必刷刷新等待及失败保留同一份列表与媒体身份', () async {
    final provider = preciousFeedProvider(Object());
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete({
      'code': 0,
      'data': {'list': [], 'media_id': 7},
    });
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).metadata?.mediaId, 7);
    final refresh = container.read(provider.notifier).onRefresh();
    expect(container.read(provider).metadata?.mediaId, 7);
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -1, 'message': '失败'});
    await refresh;
    expect(container.read(provider).loading, isA<Success>());
    expect(container.read(provider).error, isA<Error>());
    expect(container.read(provider).metadata?.mediaId, 7);
  });
}
