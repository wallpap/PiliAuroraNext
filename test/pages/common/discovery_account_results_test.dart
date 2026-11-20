import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/application/hot_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/application/curated_feed.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account() => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'fixture'}),
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
  final cases =
      <
        String,
        NotifierProvider<
          DiscoveryListing<HotVideoItemModel, void>,
          DiscoveryListingState<HotVideoItemModel, void>
        >
        Function()
      >{
        '热门': () => hotFeedProvider(Object()),
        '入站必刷': () => preciousFeedProvider(Object()),
      };
  for (final entry in cases.entries) {
    test('${entry.key}固定推荐请求账号，换凭据后丢弃旧响应并能刷新', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = entry.value();
      container
        ..listen(provider, (_, _) {})
        ..read(provider);
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
      };
      requests[0].reply.complete(body);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).loading, isA<Loading>());
      requests[1].reply.complete(body);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).loading, isA<Success>());
    });
  }
}
