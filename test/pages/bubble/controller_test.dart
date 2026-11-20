import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:pili_aurora_next/features/community/data/bubble_repository.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart'
    as refresh;
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/bubble/category_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/pages/bubble/view.dart';
import 'package:pili_aurora_next/features/community/application/bubble_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/community/domain/bubble_catalog.dart';
import 'package:pili_aurora_next/models/remote/bubble/dyn_list.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Repository extends BubbleRepository {
  _Repository({this.itemCount = 0});
  final int itemCount;
  final queries = <String>[];
  Future<void>? rootRefresh;
  @override
  Future<LoadingState<DiscoveryPage<DynList, BubbleCatalog>>> page(
    Account account, {
    required String tribeId,
    String? categoryId,
    int? sortType,
    required int page,
    BubbleCatalog? previous,
  }) async {
    queries.add('$tribeId/$categoryId');
    if (categoryId == null) await rootRefresh;
    return Success(
      DiscoveryPage(
        List.generate(
          itemCount,
          (index) =>
              DynList(dynId: '$index', title: '${categoryId ?? 'all'}:$index'),
        ),
        hasMore: false,
        metadata:
            previous ??
            BubbleCatalog(
              title: tribeId,
              categories: [
                CategoryList(id: 'all', name: '全部'),
                CategoryList(id: 'same', name: '同名分类'),
              ],
            ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledInterceptor interceptor;
  late ProviderContainer container;
  late BubbleFeed controller;
  late BubbleQuery query;
  DiscoveryListingState<DynList, BubbleCatalog> getState() =>
      container.read(bubbleFeedProvider(query));
  var closed = false;
  LoginAccount login(String credential) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '100', 'bili_jct': credential}),
    'access-$credential',
    null,
  )..activated = true;
  Map<String, Object> response(String id) => {
    'code': 0,
    'data': {
      'content': {
        'dyn_list': [
          {'dyn_id': id, 'title': id},
        ],
      },
    },
  };
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    Accounts.account = MemoryBox<LoginAccount>();
    AnonymousAccount().activated = true;
    Request();
    Request.dio.interceptors.clear();
  });
  setUp(() {
    closed = false;
    interceptor = ControlledInterceptor();
    Request.dio.interceptors.add(interceptor);
    Accounts.accountMode[AccountType.main.index] = login('old');
    container = ProviderContainer();
    query = (owner: Object(), tribeId: '1', categoryId: null, sortType: null);
    container.listen(bubbleFeedProvider(query), (_, _) {});
    controller = container.read(bubbleFeedProvider(query).notifier);
  });
  tearDown(() async {
    if (!closed) container.dispose();
    for (final request in interceptor.requests) {
      if (!request.reply.isCompleted) {
        request.reply.complete(response('retired'));
      }
    }
    Request.dio.interceptors.remove(interceptor);
    await interceptor.close();
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
  });
  test('同 UID 换凭据后立即重读首页，丢弃旧账号响应', () async {
    await interceptor.waitForRequests(1);
    final oldAccount = Accounts.main;
    final newAccount = login('new');
    Accounts.replaceCredentials(newAccount);
    await interceptor.waitForRequests(2);
    expect(interceptor.requests[0].options.extra['account'], same(oldAccount));
    expect(interceptor.requests[1].options.extra['account'], same(newAccount));
    interceptor.requests[1].reply.complete(response('new'));
    await Future<void>.delayed(Duration.zero);
    interceptor.requests[0].reply.complete(response('old'));
    await Future<void>.delayed(Duration.zero);
    expect(getState().loading.data.single.dynId, 'new');
  });
  test('分页失败保留列表和页码，排序使迟到分页失效', () async {
    await interceptor.waitForRequests(1);
    interceptor.requests[0].reply.complete(response('first'));
    await Future<void>.delayed(Duration.zero);
    final failed = controller.onLoadMore();
    await interceptor.waitForRequests(2);
    interceptor.requests[1].reply.complete({'code': -1, 'message': '失败'});
    await failed;

    expect(getState().loading.data.single.dynId, 'first');
    final pending = controller.retry();
    await interceptor.waitForRequests(3);
    query = (
      owner: query.owner,
      tribeId: query.tribeId,
      categoryId: null,
      sortType: 2,
    );
    container.listen(bubbleFeedProvider(query), (_, _) {});
    final sorted = Future<void>.value();
    await interceptor.waitForRequests(4);
    expect(interceptor.requests[3].options.queryParameters['page_num'], 1);
    interceptor.requests[3].reply.complete(response('sorted'));
    await sorted;
    await Future<void>.delayed(Duration.zero);
    interceptor.requests[2].reply.complete(response('late'));
    await pending;
    expect(getState().loading.data.single.dynId, 'sorted');
  });
  test('释放后消费迟到响应，不更新状态', () async {
    await interceptor.waitForRequests(1);
    container.dispose();
    closed = true;
    interceptor.requests[0].reply.complete(response('late'));
    await Future<void>.delayed(Duration.zero);
  });
  testWidgets('两个小站同名分类互不争抢，目录替换与离页释放活动 Tab', (tester) async {
    // 使用页面根 ProviderScope，避免依赖测试中独立 container 的保活。
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bubbleRepositoryProvider.overrideWithValue(repository)],
        child: const GetMaterialApp(
          home: Row(
            children: [
              Expanded(child: BubblePage(tribeId: 'one')),
              Expanded(child: BubblePage(tribeId: 'two')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNWidgets(2));
    final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!
      ..animateTo(1);
    await tester.pump();
    Accounts.replaceCredentials(login('widget-new'));
    await tester.pump();
    await tester.pump();
    expect(tabs.animation, isNull);
    expect(repository.queries, containsAll(['one/null', 'two/null']));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tabs.animation, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('目录刷新保留当前分类与各自滚动，重复点击分类回顶', (tester) async {
    final repository = _Repository(itemCount: 100);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bubbleRepositoryProvider.overrideWithValue(repository)],
        child: const GetMaterialApp(home: BubblePage(tribeId: 'one')),
      ),
    );
    await tester.pumpAndSettle();
    Future<Offset> scrollToAnchor(String category) async {
      final before = tester.getTopLeft(find.text('$category:10'));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byType(CustomScrollView).hitTestable(),
          ),
          scrollDelta: const Offset(0, 200),
        ),
      );
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('$category:10'));
      expect(after.dy, lessThan(before.dy));
      return after;
    }

    final first = await scrollToAnchor('all');
    final gate = Completer<void>();
    repository.rootRefresh = gate.future;
    final operation = tester
        .widget<refresh.RefreshIndicator>(find.byType(refresh.RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(tester.getTopLeft(find.text('all:10')), first);
    await tester.tap(find.text('同名分类'));
    await tester.pumpAndSettle();
    final second = await scrollToAnchor('same');
    gate.complete();
    await operation;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('same:10')), second);
    expect(find.text('same:0').hitTestable(), findsNothing);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('all:10')), first);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('all:0').hitTestable(), findsOneWidget);
    await tester.tap(find.text('同名分类'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('same:10')), second);
    await tester.tap(find.text('同名分类'));
    await tester.pumpAndSettle();
    expect(find.text('same:0').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
