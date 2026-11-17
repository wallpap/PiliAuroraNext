import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_feed.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamics_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/models/dynamics/up.dart';
import 'package:pili_aurora_next/pages/dynamics/view.dart';
import 'package:pili_aurora_next/pages/main/controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Repository extends DynamicsRepository {
  Completer<LoadingState<FollowUpModel>>? author;
  Completer<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>>?
  listing;
  @override
  Future<LoadingState<FollowUpModel>> authors(
    Account account, {
    String? offset,
    int? followingPage,
  }) async => author == null
      ? Success(
          FollowUpModel.fromUpList(null)
            ..upList = []
            ..hasMore = false,
        )
      : author!.future;
  @override
  Future<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>> feed(
    Account account,
    DynamicsTabType type,
    int hostMid,
    Set<int> banned,
    DynamicCursor? cursor,
  ) async => listing == null
      ? const Success(
          DiscoveryPage([], metadata: DynamicCursor(null, {}), hasMore: false),
        )
      : listing!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  late DynamicsUpdates updates;
  LoginAccount account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, Object> page(
    List<String> ids,
    String offset, {
    bool more = true,
  }) => {
    'code': 0,
    'data': {
      'has_more': more,
      'offset': offset,
      'items': [
        for (final id in ids) {'id_str': id, 'modules': <String, Object>{}},
      ],
    },
  };
  DynamicsQuery query([int host = -1]) => (
    owner: Object(),
    type: host == -1 ? DynamicsTabType.all : DynamicsTabType.up,
    hostMid: host,
  );
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    GStorage.userInfo = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account();
    updates = DynamicsUpdates();
    container = ProviderContainer(
      overrides: [dynamicsUpdatesProvider.overrideWithValue(updates)],
    );
  });
  tearDown(() async {
    container.dispose();
    await updates.close();
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('同 UID 换凭据废弃旧结果，推荐角色变化不替换动态归属', () async {
    final provider = dynamicsFeedProvider(query());
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests[1].reply.complete(page(['new'], 'next'));
    await tick();
    requests[0].reply.complete(page(['old'], 'old'));
    await tick();
    expect(container.read(provider).loading.data.single.idStr, 'new');
    final source = container.read(provider).source;
    Accounts.accountMode[AccountType.recommend.index] = account('recommend');
    expect(container.read(provider).source, same(source));
  });
  test('分页互斥、失败重试原游标，重复游标结束且去重', () async {
    final provider = dynamicsFeedProvider(query());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(page(['1'], 'next'));
    await tick();
    final more = controller.onLoadMore();
    await controller.onLoadMore();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -403});
    await more;
    expect(container.read(provider).loading.data.single.idStr, '1');
    final retry = controller.retry();
    await interceptor.waitForRequests(3);
    expect(requests.last.options.queryParameters['offset'], 'next');
    requests.last.reply.complete(page(['1', '2'], 'next'));
    await retry;
    expect(container.read(provider).loading.data.map((item) => item.idStr), [
      '1',
      '2',
    ]);
    expect(container.read(provider).hasMore, isFalse);
  });
  test('删除按 ID 互斥、失败保留，分页不复活已删除动态', () async {
    final provider = dynamicsFeedProvider(query());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(page(['1'], 'next'));
    await tick();
    var remove = controller.onRemove('1');
    await interceptor.waitForRequests(2);
    expect(await controller.onRemove('1'), isA<Error>());
    requests[1].reply.complete({'code': -403});
    await remove;
    expect(container.read(provider).loading.data, hasLength(1));
    final more = controller.onLoadMore();
    await interceptor.waitForRequests(3);
    remove = controller.onRemove('1');
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': 0});
    expect((await remove).isSuccess, isTrue);
    requests[2].reply.complete(page(['1', '2'], '', more: false));
    await more;
    expect(container.read(provider).loading.data.single.idStr, '2');
  });
  test('发布失效刷新所有已订阅分类，释放后不再调度；迟到作者页不续读', () async {
    final providers = [
      dynamicsFeedProvider(query()),
      dynamicsFeedProvider(query(2)),
    ];
    for (final provider in providers) {
      container.listen(provider, (_, _) {});
    }
    await interceptor.waitForRequests(2);
    updates.published(Accounts.main);
    await interceptor.waitForRequests(4);
    for (var i = 2; i < 4; i++) {
      requests[i].reply.complete(page(['new'], '', more: false));
    }
    for (var i = 0; i < 2; i++) {
      requests[i].reply.complete(page(['old'], 'next'));
    }
    await tick();
    for (final provider in providers) {
      expect(container.read(provider).loading.data.single.idStr, 'new');
    }
    container.dispose();
    updates.published(Accounts.main);
    await tick();
    expect(requests, hasLength(4));
  });
  test('折叠展开只修改当前快照内指定 ID', () async {
    final provider = dynamicsFeedProvider(query());
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(page(['fold', '2', '3'], '', more: false));
    await tick();
    final items = container.read(provider).loading.data;
    items.first.modules.moduleFold = ModuleFold.fromJson({
      'ids': ['filtered', '2'],
    });
    items[1].visible = items[2].visible = false;
    container.read(provider.notifier).onUnfold(items.first);
    expect(items.first.modules.moduleFold, isNull);
    expect(items[1].visible, isTrue);
    expect(items[2].visible, isFalse);
  });
  test('首屏在途也排除其他入口已确认删除的 ID，释放后过滤页不续读', () async {
    final provider = dynamicsFeedProvider(query());
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    updates.removed(Accounts.main, '1');
    requests[0].reply.complete(page(['1', '2'], '', more: false));
    await tick();
    expect(container.read(provider).loading.data.single.idStr, '2');
    final refresh = container.read(provider.notifier).onRefresh();
    await interceptor.waitForRequests(2);
    container.dispose();
    requests[1].reply.complete(page([], 'next'));
    await refresh;
    expect(requests, hasLength(2));
  });
  testWidgets('父刷新等待作者与分类，活动 Tab 和滚动在卸载时释放', (tester) async {
    final repository = _Repository();
    await GStorage.setting.put(SettingBoxKey.navBarSort, [1]);
    await GStorage.setting.put(SettingBoxKey.autoUpdate, false);
    final main = Get.put<MainController>(MainController());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dynamicsRepositoryProvider.overrideWithValue(repository)],
        child: const GetMaterialApp(home: DynamicsPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(main.dynamicController, isNotNull);
    repository
      ..author = Completer()
      ..listing = Completer();
    var finished = false;
    final refresh = main.dynamicController!.onRefresh().then(
      (_) => finished = true,
    );
    repository.author!.complete(
      Success(FollowUpModel.fromUpList(null)..upList = []),
    );
    await tester.pump();
    expect(finished, isFalse);
    repository.listing!.complete(
      const Success(
        DiscoveryPage([], metadata: DynamicCursor(null, {}), hasMore: false),
      ),
    );
    await refresh;
    expect(finished, isTrue);
    tester.widget<TabBar>(find.byType(TabBar).first).controller!.animateTo(1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(main.dynamicController, isNull);
    expect(tester.takeException(), isNull);
  });
}
