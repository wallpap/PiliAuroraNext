import 'dart:async';

import 'package:pili_aurora_next/http/validate.dart';
import 'package:pili_aurora_next/features/search/presentation/search_verification_dialog.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart' show Error;
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/search/application/search_results.dart';
import 'package:pili_aurora_next/features/search/domain/result.dart';
import 'package:pili_aurora_next/pages/search_result/view.dart';
import 'package:pili_aurora_next/features/search/domain/filters/search_type.dart';
import 'package:pili_aurora_next/features/content_discovery/application/blocked_authors.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  final dispatched = interceptor.waitForRequests;
  late ProviderContainer container;
  late LoginAccount account;
  LoginAccount login(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '100', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  SearchResultsQuery query({
    SearchType type = SearchType.video,
    String keyword = 'test',
    Object? owner,
    String filters = '{}',
    Object? revision,
  }) => (
    keyword: keyword,
    type: type,
    owner: owner ?? type,
    filters: filters,
    revision: revision ?? type,
  );
  Map<String, dynamic> video(int id, {int mid = 200}) => {
    'aid': id,
    'bvid': 'BV$id',
    'title': 'video$id',
    'mid': mid,
    'author': 'user$mid',
    'duration': '1:00',
  };
  Map<String, dynamic> page(
    List<int> ids, {
    int total = 80,
    bool all = false,
  }) => {
    'code': 0,
    'data': {
      'numResults': total,
      'result': all
          ? [
              {
                'result_type': 'video',
                'data': [for (final id in ids) video(id)],
              },
              {
                'result_type': 'bili_user',
                'data': [
                  {'mid': 2, 'uname': 'two'},
                ],
              },
            ]
          : [for (final id in ids) video(id)],
    },
  };
  List<int> range(int start, int count) =>
      List.generate(count, (index) => start + index);
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    Accounts.account = MemoryBox<LoginAccount>();
    AnonymousAccount().activated = true;
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        interceptor,
      );
  });
  setUp(() {
    requests.clear();
    for (final mid in [200, 500]) {
      BlockedAuthors.setBlocked(mid, false);
    }
    GStorage.localCache.put(
      LocalCacheKey.mixinKey,
      '01234567890123456789012345678901',
    );
    GStorage.localCache.put(
      LocalCacheKey.timeStamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    account = login('old');
    Accounts.accountMode[AccountType.main.index] = account;
    Accounts.accountMode[AccountType.recommend.index] = account;
    (GStorage.setting as MemoryBox).data.clear();
    GStorage.setting.put(SettingBoxKey.filterBlockedAuthors, false);
    container = ProviderContainer();
  });
  tearDown(() {
    container.dispose();
    for (final request in requests) {
      if (!request.reply.isCompleted) {
        request.reply.complete({'code': -1, 'message': 'closed'});
      }
    }
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('搜索和黑名单并行，黑名单未完成时不发布结果', () async {
    GStorage.setting.put(SettingBoxKey.filterBlockedAuthors, true);
    final provider = searchResultsProvider(query());
    container.listen(provider, (_, _) {});
    await dispatched(2);
    final blacklist = requests.singleWhere(
      (r) => r.options.path == Api.blackLst,
    );
    final search = requests.singleWhere((r) => r.options.path != Api.blackLst);
    search.reply.complete(page([1], total: 1));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).isLoading, isTrue);
    blacklist.reply.complete({
      'code': 0,
      'data': {'total': 0, 'list': []},
    });
    expect((await container.read(provider.future)).items.single.aid, 1);
  });

  test('普通结果先发布，合作卡片保持原位并在核验后移除', () async {
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    GStorage.setting.put(SettingBoxKey.filterBlockedAuthors, true);
    GStorage.setting.put(SettingBoxKey.checkCooperativeAuthors, true);
    BlockedAuthors.setBlocked(500, true);
    final provider = searchResultsProvider(query());
    final settled = Completer<SearchResultsState>();
    container.listen(provider, (_, next) {
      if (next.value case final data? when !data.loadingMore) {
        settled.complete(data);
      }
    });
    await dispatched(1);
    requests.single.reply.complete({
      'code': 0,
      'data': {
        'numResults': 3,
        'result': [
          video(40),
          {...video(41), 'is_union_video': 1},
          video(42),
        ],
      },
    });
    await dispatched(2);
    final first = await container.read(provider.future);
    expect(first.items.map((item) => item.aid), [40, 41, 42]);
    expect((first.pendingItems.single as SearchVideoItemModel).aid, 41);
    expect(requests.last.options.path, Api.videoIntro);
    requests.last.reply.complete({
      'code': 0,
      'data': {
        'staff': [
          {'mid': 500},
        ],
      },
    });
    final finalPage = await settled.future;
    expect(finalPage.items.map((item) => item.aid), [40, 42]);
    expect(finalPage.pendingItems, isEmpty);
  });

  test('分类、关键词、页面与筛选快照隔离，请求固定推荐账号', () async {
    final recommend = login('recommend');
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    final queries = [
      query(),
      query(keyword: 'other'),
      query(owner: Object()),
      query(
        filters:
            '{"order":"click","duration":1,"tids":4,"pubBegin":1,"pubEnd":2}',
      ),
      query(type: SearchType.bili_user),
    ];
    for (final q in queries) {
      container.listen(searchResultsProvider(q), (_, _) {});
    }
    await dispatched(5);
    for (final request in requests) {
      expect(request.options.extra['account'], same(recommend));
      if (request.options.queryParameters['order'] == 'click') {
        expect(request.options.queryParameters['duration'], 1);
        expect(request.options.queryParameters['tids'], 4);
        expect(request.options.queryParameters['pubtime_begin_s'], 1);
      }
      request.reply.complete(
        request.options.queryParameters['search_type'] == 'bili_user'
            ? {
                'code': 0,
                'data': {
                  'numResults': 1,
                  'result': [
                    {'mid': 5, 'uname': 'five'},
                  ],
                },
              }
            : page([1], total: 1),
      );
    }
    for (final q in queries) {
      await container.read(searchResultsProvider(q).future);
    }
    expect(
      container
          .read(searchResultsProvider(queries.last))
          .requireValue
          .items
          .single
          .mid,
      5,
    );
    expect(
      () => container
          .read(searchResultsProvider(queries.first))
          .requireValue
          .items
          .clear(),
      throwsUnsupportedError,
    );
  });

  test('综合首屏保留卡片，后续页请求视频；分页串行失败重试与去重', () async {
    final q = query(type: SearchType.all);
    final provider = searchResultsProvider(q);
    container.listen(provider, (_, _) {});
    await dispatched(1);
    expect(requests.single.options.path, Api.searchAll);
    requests.single.reply.complete(page(range(1, 20), all: true));
    final first = await container.read(provider.future);
    expect(first.users.single.mid, 2);
    final notifier = container.read(provider.notifier);
    final more = notifier.loadMore();
    await notifier.loadMore();
    await dispatched(2);
    expect(requests.last.options.path, Api.searchByType);
    expect(requests.last.options.queryParameters['search_type'], 'video');
    expect(requests.last.options.queryParameters['page'], 2);
    requests.last.reply.complete({'code': -1, 'message': 'failed'});
    await more;
    expect(container.read(provider).requireValue.nextPage, 2);
    expect(container.read(provider).requireValue.users.single.mid, 2);
    await notifier.loadMore();
    expect(requests, hasLength(2));
    final retry = notifier.loadMore(retry: true);
    await dispatched(3);
    requests.last.reply.complete(page(range(20, 20)));
    await retry;
    expect(container.read(provider).requireValue.items, hasLength(39));
    expect(first.items, hasLength(20));
    final duplicate = notifier.loadMore();
    await dispatched(4);
    requests.last.reply.complete(page(range(20, 20)));
    await duplicate;
    expect(container.read(provider).requireValue.hasMore, isFalse);
  });

  test('综合筛选直接查询视频，分页期间移除项不被迟到结果恢复', () async {
    final q = query(
      type: SearchType.all,
      filters: '{"order":"click","filtered":true}',
    );
    final provider = searchResultsProvider(q);
    container.listen(provider, (_, _) {});
    await dispatched(1);
    expect(requests.single.options.path, Api.searchByType);
    requests.single.reply.complete(page(range(1, 20)));
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final more = notifier.loadMore();
    await dispatched(2);
    notifier.remove(container.read(provider).requireValue.items.first);
    requests.last.reply.complete(page(range(20, 20)));
    await more;
    expect(
      container
          .read(provider)
          .requireValue
          .items
          .any((dynamic e) => e.aid == 1),
      isFalse,
    );
  });

  test('分页失败和重试保留请求期间移除的卡片', () async {
    final provider = searchResultsProvider(query());
    container.listen(provider, (_, _) {});
    await dispatched(1);
    requests.single.reply.complete(page(range(1, 20)));
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final more = notifier.loadMore();
    await dispatched(2);
    notifier.remove(container.read(provider).requireValue.items.first);
    requests.last.reply.complete({'code': -1, 'message': 'failed'});
    await more;
    final failed = container.read(provider).requireValue;
    expect(failed.items, hasLength(19));
    expect(failed.items.any((dynamic e) => e.aid == 1), isFalse);
    expect(failed.nextPage, 2);
    expect(failed.loadingMore, isFalse);
    expect(failed.error, isNotNull);
    final retry = notifier.loadMore(retry: true);
    await dispatched(3);
    requests.last.reply.complete(page(range(20, 20)));
    await retry;
    expect(
      container
          .read(provider)
          .requireValue
          .items
          .any((dynamic e) => e.aid == 1),
      isFalse,
    );
  });

  test('同 UID 新凭据切换和刷新丢弃旧分页，错误态保留值禁止分页', () async {
    final q = query();
    final provider = searchResultsProvider(q);
    container.listen(provider, (_, _) {});
    await dispatched(1);
    requests.single.reply.complete(page(range(1, 20)));
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final more = notifier.loadMore();
    await dispatched(2);
    Accounts.accountMode[AccountType.recommend.index] = login('new');
    await Accounts.refresh();
    await container.pump();
    await dispatched(3);
    requests.last.reply.complete(page([99], total: 1));
    await container.read(provider.future);
    requests[1].reply.complete(page(range(21, 20)));
    await more;
    expect(container.read(provider).requireValue.items.single.aid, 99);
    container.invalidate(provider);
    await container.pump();
    await dispatched(4);
    requests.last.reply.complete({'code': -1, 'message': 'failed'});
    await expectLater(
      container.read(provider.future),
      throwsA(isA<Error>().having((error) => error.code, 'business code', -1)),
    );
    await notifier.loadMore();
    expect(requests, hasLength(4));
  });

  test('验证重查固定原页和筛选，重复提交与过期验证失效', () async {
    final q = query(filters: '{"order":"click"}');
    final provider = searchResultsProvider(q);
    container.listen(provider, (_, _) {});
    await dispatched(1);
    requests.single.reply.complete({
      'code': 0,
      'data': {'v_voucher': 'voucher'},
    });
    await expectLater(
      container.read(provider.future),
      throwsA(isA<SearchVerificationRequired>()),
    );
    final challenge =
        container.read(provider).error! as SearchVerificationRequired;
    final notifier = container.read(provider.notifier);
    final verify = notifier.verify(challenge, 'verified');
    await notifier.verify(challenge, 'duplicate');
    await dispatched(2);
    expect(requests.last.options.queryParameters['page'], 1);
    expect(requests.last.options.queryParameters['order'], 'click');
    expect(requests.last.options.queryParameters['gaia_vtoken'], 'verified');
    requests.last.reply.complete(page([1], total: 1));
    await verify;
    await notifier.verify(challenge, 'stale');
    expect(requests, hasLength(2));
    container.invalidate(provider);
    await container.pump();
    await dispatched(3);
    requests.last.reply.complete(page([2], total: 1));
    await container.read(provider.future);
    await notifier.verify(challenge, 'stale');
    expect(requests, hasLength(3));
  });

  test('验证注册绑定发起账号，页面失效后不再打开验证或回调', () async {
    var current = true;
    var callbacks = 0;
    final registration = showSearchVerification(
      'voucher',
      (_) => callbacks++,
      account: account,
      isCurrent: () => current,
    );
    await dispatched(1);
    expect(requests.single.options.path, Api.gaiaVgateRegister);
    expect(requests.single.options.extra['account'], same(account));
    expect(requests.single.options.extra['noRetry'], isTrue);
    expect(requests.single.options.queryParameters['csrf'], 'old');
    current = false;
    requests.single.reply.complete({
      'code': 0,
      'data': {
        'geetest': {'gt': 'gt', 'challenge': 'challenge'},
        'token': 'fixture',
      },
    });
    await registration;
    expect(callbacks, 0);
    expect(requests, hasLength(1));
  });

  test('验证提交使用原账号 CSRF 与 HTTP 上下文且不自动重试', () async {
    final submit = ValidateHttp.gaiaVgateValidate(
      account: account,
      challenge: 'challenge',
      seccode: 'fixture',
      token: 'fixture',
      validate: 'fixture',
    );
    Accounts.accountMode[AccountType.main.index] = login('new');
    await dispatched(1);
    expect(requests.single.options.path, Api.gaiaVgateValidate);
    expect(requests.single.options.extra['account'], same(account));
    expect(requests.single.options.queryParameters['csrf'], 'old');
    expect(requests.single.options.extra['noRetry'], isTrue);
    requests.single.reply.complete({
      'code': 0,
      'data': {'is_valid': 1, 'grisk_id': 'fixture'},
    });
    expect((await submit).isSuccess, isTrue);
  });

  test('屏蔽过滤沿原始页补足，连续五页无增长停止', () async {
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    GStorage.setting.put(SettingBoxKey.filterBlockedAuthors, true);
    BlockedAuthors.setBlocked(200, true);
    final q = query();
    final provider = searchResultsProvider(q);
    final settled = Completer<SearchResultsState>();
    container.listen(provider, (_, next) {
      if (next.value case final data? when !data.loadingMore) {
        settled.complete(data);
      }
    });
    for (var i = 0; i < 5; i++) {
      await dispatched(i + 1);
      requests[i].reply.complete(page(range(i * 20 + 1, 20), total: 500));
    }
    final data = await settled.future;
    expect(data.items, isEmpty);
    expect(data.nextPage, 6);
    expect(data.hasMore, isFalse);
  });

  test('主账号改变时重算过滤且隔离旧响应，推荐账号保持不变', () async {
    final q = query();
    final provider = searchResultsProvider(q);
    container.listen(provider, (_, _) {});
    await dispatched(1);
    Accounts.accountMode[AccountType.main.index] = login('main-new');
    await Accounts.refresh();
    await container.pump();
    await dispatched(2);
    expect(requests.last.options.extra['account'], same(account));
    requests.last.reply.complete(page([2], total: 1));
    await container.read(provider.future);
    requests.first.reply.complete(page([1], total: 1));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).requireValue.items.single.aid, 2);
  });

  test('过滤空页沿新页码补足，综合卡片保留首屏快照', () async {
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    GStorage.setting.put(SettingBoxKey.filterBlockedAuthors, true);
    BlockedAuthors.setBlocked(200, true);
    final q = query(type: SearchType.all);
    final provider = searchResultsProvider(q);
    final settled = Completer<SearchResultsState>();
    container.listen(provider, (_, next) {
      if (next.value case final data? when !data.loadingMore) {
        settled.complete(data);
      }
    });
    await dispatched(1);
    requests.single.reply.complete(page(range(1, 20), all: true));
    await dispatched(2);
    final first = await container.read(provider.future);
    expect(first.users.single.mid, 2);
    expect(first.loadingMore, isTrue);
    expect(requests.last.options.queryParameters['page'], 2);
    expect(requests.last.options.queryParameters['search_type'], 'video');
    requests.last.reply.complete({
      'code': 0,
      'data': {
        'numResults': 80,
        'result': [for (final id in range(21, 20)) video(id, mid: 300)],
      },
    });
    final data = await settled.future;
    expect(data.items, hasLength(20));
    expect(data.items.first.aid, 21);
    expect(data.users.single.mid, 2);
    expect(data.nextPage, 3);
  });

  test('释放挂起的查询后不再发补页或响应验证', () async {
    final q = query();
    final provider = searchResultsProvider(q);
    final sub = container.listen(provider, (_, _) {});
    await dispatched(1);
    sub.close();
    await container.pump();
    requests.single.reply.complete(page([1]));
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
  });

  testWidgets('切换分类和视频排序后，只显示当前查询的计数', (tester) async {
    Future<void> waitForSearch(int requestCount) async {
      for (var frame = 0; frame < 60; frame++) {
        if (requests.length >= requestCount) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(requests, hasLength(requestCount));
    }

    Future<void> reply(
      int requestCount, {
      required String type,
      required int total,
      String? order,
    }) async {
      await waitForSearch(requestCount);
      final request = requests.last;
      expect(request.options.queryParameters['search_type'], type);
      expect(request.options.queryParameters['order'], order);
      request.reply.complete(page([], total: total));
      await tester.pumpAndSettle();
      expect(requests, hasLength(requestCount));
    }

    final selected = <int>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: GetMaterialApp(
          getPages: [
            GetPage(name: '/results', page: () => const SearchResultPage()),
          ],
          home: Builder(
            builder: (_) => TextButton(
              onPressed: () => Get.toNamed<void>(
                '/results',
                parameters: {'keyword': 'test'},
                arguments: {'fromSearch': true, 'onIndexChanged': selected.add},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await reply(1, type: 'all', total: 3);
    expect(find.text('综合 3'), findsOneWidget);
    await tester.tap(find.text('视频'));
    await reply(2, type: 'video', total: 120);
    expect(selected.last, SearchType.video.index);
    expect(find.text('视频 99+'), findsOneWidget);

    await tester.tap(find.text('播放多'));
    await waitForSearch(3);
    expect(find.text('视频 99+'), findsNothing);
    await reply(3, type: 'video', order: 'click', total: 125);
    expect(find.text('视频 99+'), findsOneWidget);

    await tester.tap(find.text('新发布'));
    await waitForSearch(4);
    expect(find.text('视频'), findsOneWidget);
    await reply(4, type: 'video', order: 'pubdate', total: 99);
    expect(find.text('视频 99'), findsOneWidget);
    expect(find.text('综合 3'), findsOneWidget);

    await tester.tap(find.text('弹幕多'));
    await waitForSearch(5);
    await tester.tap(find.text('test'));
    await tester.pumpAndSettle();
    await reply(5, type: 'video', order: 'dm', total: 5);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('视频 5'), findsNothing);
  });
}
