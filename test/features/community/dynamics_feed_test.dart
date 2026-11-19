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
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Repository extends DynamicsRepository {
  int authorFeedLength = 1;
  final queriedAuthors = <int>[];
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
            ..upList = [
              UpItem(mid: 2, uname: '关注作者'),
              UpItem(mid: 3, uname: '另一位作者'),
            ]
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
  ) async {
    if (type == DynamicsTabType.up) queriedAuthors.add(hostMid);
    return listing == null
        ? Success(
            DiscoveryPage(
              [
                for (
                  var index = 0;
                  index < (type == DynamicsTabType.up ? authorFeedLength : 1);
                  index++
                )
                  DynamicItemModel.fromJson({
                    'id_str': '$hostMid-$index',
                    'type': 'DYNAMIC_TYPE_WORD',
                    'modules': {
                      'module_author': {
                        'mid': 1,
                        'name': index == 0 && type == DynamicsTabType.all
                            ? '卡片作者'
                            : '$hostMid 的动态 $index',
                      },
                      'module_stat': {
                        'forward': {'count': 0},
                        'comment': {'count': 0},
                        'like': {'count': 0, 'status': false},
                      },
                    },
                  }),
              ],
              metadata: const DynamicCursor(null, {}),
              hasMore: false,
            ),
          )
        : await listing!.future;
  }
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
    Accounts.replaceCredentials(account('third'));
    expect(container.read(provider).loading, isA<Loading>());
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(page(['third'], '', more: false));
    await tick();
    expect(container.read(provider).loading.data.single.idStr, 'third');
  });
  test('分页互斥、失败重试原游标，重复游标结束，刷新后使用新游标', () async {
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
    final refresh = controller.onRefresh();
    await interceptor.waitForRequests(4);
    expect(requests.last.options.queryParameters['offset'], isNull);
    requests.last.reply.complete(page(['3'], 'fresh-next'));
    await refresh;
    final next = controller.onLoadMore();
    await interceptor.waitForRequests(5);
    expect(requests.last.options.queryParameters['offset'], 'fresh-next');
    requests.last.reply.complete(page(['4'], '', more: false));
    await next;
    expect(container.read(provider).loading.data.map((item) => item.idStr), [
      '3',
      '4',
    ]);
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
  testWidgets('父刷新保持可见内容并等待作者与分类，离页释放活动资源', (tester) async {
    final repository = _Repository();
    DiscoveryPageHandle? handle;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dynamicsRepositoryProvider.overrideWithValue(repository)],
        child: GetMaterialApp(
          home: DynamicsPage(
            register: (actions) {
              handle = actions;
              return () => handle = null;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(handle, isNotNull);
    expect(find.text('卡片作者'), findsOneWidget);
    expect(find.text('关注作者'), findsOneWidget);
    repository
      ..author = Completer()
      ..listing = Completer();
    var finished = false;
    final refresh = handle!.onRefresh().then(
      (_) => finished = true,
    );
    await tester.pump();
    expect(find.text('卡片作者'), findsOneWidget);
    expect(find.text('关注作者'), findsOneWidget);
    repository.author!.complete(
      Success(FollowUpModel.fromUpList(null)..upList = []),
    );
    await tester.pumpAndSettle();
    expect(finished, isFalse);
    expect(find.text('卡片作者'), findsOneWidget);
    expect(find.text('关注作者'), findsNothing);
    repository.listing!.complete(
      const Success(
        DiscoveryPage([], metadata: DynamicCursor(null, {}), hasMore: false),
      ),
    );
    await refresh;
    await tester.pump();
    expect(finished, isTrue);
    expect(find.text('卡片作者'), findsNothing);
    tester.widget<TabBar>(find.byType(TabBar).first).controller!.animateTo(1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(handle, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复选择作者刷新并回顶，切换作者的列表从顶部打开', (tester) async {
    final repository = _Repository()..authorFeedLength = 30;
    late DiscoveryPageHandle handle;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dynamicsRepositoryProvider.overrideWithValue(repository)],
        child: GetMaterialApp(
          home: DynamicsPage(
            register: (actions) {
              handle = actions;
              return () {};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> select(String author) async {
      await tester.tap(find.text(author));
      await tester.pumpAndSettle();
    }

    await select('关注作者');
    final first = find.text('2 的动态 0');
    expect(first, findsOneWidget);
    handle.scrollController.jumpTo(360);
    await tester.pumpAndSettle();
    expect(first.hitTestable(), findsNothing);
    final reads = repository.queriedAuthors.where((mid) => mid == 2).length;
    await select('关注作者');
    expect(first.hitTestable(), findsOneWidget);
    expect(
      repository.queriedAuthors.where((mid) => mid == 2),
      hasLength(reads + 1),
    );

    handle.scrollController.jumpTo(360);
    await tester.pumpAndSettle();
    await select('另一位作者');
    expect(find.text('3 的动态 0').hitTestable(), findsOneWidget);
    handle.scrollController.jumpTo(360);
    await tester.pumpAndSettle();
    await select('关注作者');
    expect(first.hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
