import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/rank_feed.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account() => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '3', 'bili_jct': 'fixture'}),
    null,
    null,
  );
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
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    Accounts.accountMode[AccountType.recommend.index] = account();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  for (final category in [
    (rid: 1, seasonType: null),
    (rid: null, seasonType: 1),
    (rid: null, seasonType: 2),
  ]) {
    test('排行榜 $category 固定推荐账号，同 UID 换凭据淘汰旧响应且不分页', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = rankFeedProvider((
        owner: Object(),
        rid: category.rid,
        seasonType: category.seasonType,
      ));
      container.listen(provider, (_, _) {});
      container.read(provider);
      await interceptor.waitForRequests(1);
      final before = Accounts.get(AccountType.recommend);
      expect(requests[0].options.extra['account'], same(before));
      final replacement = account();
      Accounts.replaceCredentials(replacement);
      expect(container.read(provider).loading, isA<Loading>());
      await interceptor.waitForRequests(2);
      expect(requests[1].options.extra['account'], same(replacement));
      const body = {
        'code': 0,
        'data': {'list': []},
        'result': {'list': []},
      };
      requests[0].reply.complete(body);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).loading, isA<Loading>());
      requests[1].reply.complete(body);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).loading.dataOrNull, isEmpty);
      expect(container.read(provider).hasMore, isFalse);
      await container.read(provider.notifier).onLoadMore();
      expect(requests.length, 2);
    });
  }
  test('同分类的两个页面有独立刷新所有者', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = rankFeedProvider((owner: Object(), rid: 1, seasonType: null));
    final second = rankFeedProvider((
      owner: Object(),
      rid: 1,
      seasonType: null,
    ));
    container
      ..listen(first, (_, _) {})
      ..listen(second, (_, _) {})
      ..read(first)
      ..read(second);
    await interceptor.waitForRequests(2);
    final refresh = container.read(first.notifier).onRefresh();
    await interceptor.waitForRequests(3);
    const body = {
      'code': 0,
      'data': {'list': []},
    };
    requests[1].reply.complete(body);
    requests[2].reply.complete(body);
    await refresh;
    requests[0].reply.complete(body);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(first).loading, isA<Success>());
    expect(container.read(second).loading, isA<Success>());
  });
}
