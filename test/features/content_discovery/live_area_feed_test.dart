import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_discovery/application/live_area_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/data/live_catalog_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/remote/live/live_area_list/area_item.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/pages/live_area_detail/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';
import 'live_fixture.dart';

class _Repository extends LiveCatalogRepository {
  final directories =
      <Completer<LoadingState<DiscoveryPage<AreaItem, void>>>>[];
  @override
  Future<LoadingState<DiscoveryPage<AreaItem, void>>> directory(
    Account account,
    Object? parentId,
  ) {
    final result = Completer<LoadingState<DiscoveryPage<AreaItem, void>>>();
    directories.add(result);
    return result.future;
  }

  @override
  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> area(
    Account account,
    int page, {
    required Object? areaId,
    required Object? parentAreaId,
    String? sortType,
    LiveCatalog? previous,
  }) async =>
      Success(DiscoveryPage([], metadata: LiveCatalog(), hasMore: false));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  LoginAccount account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture'}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, Object> directory(String id) => {
    'code': 0,
    'data': [
      {'id': id, 'parent_id': 8},
    ],
  };
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    container = ProviderContainer();
    Accounts.accountMode[AccountType.main.index] = account(2);
    Accounts.accountMode[AccountType.recommend.index] = account(3);
  });
  tearDown(() => container.dispose());
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  test('目录只属于推荐角色，同 UID 换凭据撤销旧目录，失败可重试', () async {
    final provider = liveDirectoryProvider((owner: Object(), parentId: 8));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    final source = container.read(provider).source;
    Accounts.replaceCredentials(account(2));
    expect(container.read(provider).source, same(source));
    await tick();
    expect(requests.length, 1);
    final replacement = account(3);
    Accounts.replaceCredentials(replacement);
    expect(container.read(provider).loading, isA<Loading>());
    await interceptor.waitForRequests(2);
    expect(requests[1].options.extra['account'], same(replacement));
    requests[1].reply.complete({'code': -42, 'message': '暂不可用'});
    await tick();
    requests[0].reply.complete(directory('2'));
    await tick();
    expect(container.read(provider).loading.toString(), '暂不可用');
    final retry = container.read(provider.notifier).onReload();
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(directory('3'));
    await retry;
    expect(container.read(provider).loading.data.single.id, '3');
    expect(container.read(provider).hasMore, isFalse);
  });
  test('子分区换凭据及过滤账号变化隐藏旧标签，保留错误与重试入口', () async {
    final provider = liveAreaFeedProvider((
      owner: Object(),
      areaId: 7,
      parentAreaId: 8,
      sortType: null,
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    final replacement = account(3);
    Accounts.replaceCredentials(replacement);
    expect(container.read(provider).metadata, isNull);
    await interceptor.waitForRequests(2);
    expect(requests[1].options.extra['account'], same(replacement));
    requests[1].reply.complete(liveSecond([22]));
    await tick();
    requests[0].reply.complete(liveSecond([11]));
    await tick();
    expect(container.read(provider).loading.data.single.roomid, 22);
    Accounts.replaceCredentials(account(2));
    expect(container.read(provider).metadata, isNull);
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({'code': -42, 'message': '分区暂不可用'});
    await tick();
    expect(container.read(provider).loading.toString(), '分区暂不可用');
    final retry = container.read(provider.notifier).onReload();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(liveSecond([23]));
    await retry;
    expect(container.read(provider).loading.data.single.roomid, 23);
  });
  test('子分区标签是独立查询，离页后的结果不发布也不续页', () async {
    final owner = Object();
    final first = liveAreaFeedProvider((
      owner: owner,
      areaId: 7,
      parentAreaId: 8,
      sortType: null,
    ));
    final oldSubscription = container.listen(first, (_, _) {});
    container.read(first);
    await interceptor.waitForRequests(1);
    oldSubscription.close();
    await container.pump();
    final next = liveAreaFeedProvider((
      owner: owner,
      areaId: 7,
      parentAreaId: 8,
      sortType: 'online',
    ));
    final subscription = container.listen(next, (_, _) {});
    container.read(next);
    await interceptor.waitForRequests(2);
    expect(requests[1].options.queryParameters['sort_type'], 'online');
    requests[0].reply.complete(liveSecond([11]));
    subscription.close();
    await container.pump();
    requests[1].reply.complete(liveSecond([22], count: 10));
    await tick();
    expect(container.exists(next), isFalse);
    expect(requests.length, 2);
  });
  testWidgets('目录替换与离页释放 Widget 持有的活动 TabController', (tester) async {
    final repository = _Repository();
    final widgetContainer = ProviderContainer(
      overrides: [liveCatalogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(widgetContainer.dispose);
    Get.testMode = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: widgetContainer,
        child: const GetMaterialApp(
          home: LiveAreaDetailPage(
            areaId: 3,
            parentAreaId: 8,
            parentName: '测试分区',
          ),
        ),
      ),
    );
    await tester.pump();
    repository.directories[0].complete(
      const Success(
        DiscoveryPage(
          [
            AreaItem(id: '2', parentId: 8, name: '分区二'),
            AreaItem(id: '3', parentId: 8, name: '分区三'),
          ],
          metadata: null,
          hasMore: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final first = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(first.index, 1);
    first.animateTo(0);
    await tester.pump(const Duration(milliseconds: 10));
    widgetContainer.invalidate(liveDirectoryProvider);
    await tester.pump();
    expect(first.animation, isNull);
    repository.directories[1].complete(
      const Success(
        DiscoveryPage(
          [AreaItem(id: '3', parentId: 8, name: '分区三')],
          metadata: null,
          hasMore: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final next = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(next.length, 1);
    expect(next, isNot(same(first)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(next.animation, isNull);
    expect(tester.takeException(), isNull);
  });
}
