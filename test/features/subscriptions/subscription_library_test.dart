import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_library.dart';
import 'package:pili_aurora_next/features/subscriptions/data/hidden_media.dart';
import 'package:pili_aurora_next/features/subscriptions/data/subscription_repository.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_detail.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_page.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscription_detail_page.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/memory_box.dart';

class FakeSubscriptions extends SubscriptionRepository {
  Future<LoadingState<SubData>> Function(Account, int)? readList;
  Future<LoadingState<SubDetailData>> Function(Account, int, int)? readDetail;
  Future<LoadingState<void>> Function()? mutation;
  final requests = <({Account account, int? id, int page})>[];
  final hiddenReads = <Account>[];
  final cancellations = <({Account account, int? id, int? type})>[];
  var total = 21;
  var items = [SubItemModel(id: 1, type: 21, state: 1)];
  @override
  Future<LoadingState<SubData>> subscriptions(Account account, int page) {
    requests.add((account: account, id: null, page: page));
    return readList?.call(account, page) ??
        Future.value(Success(SubData(list: [...items], hasMore: false)));
  }

  @override
  Future<LoadingState<SubDetailData>> detail(
    Account account,
    int id,
    int page,
  ) {
    requests.add((account: account, id: id, page: page));
    return readDetail?.call(account, id, page) ??
        Future.value(
          Success(
            SubDetailData(
              info: SubItemModel(
                id: id,
                type: 21,
                mediaCount: total,
                title: '合集 $id',
              ),
              medias: [
                for (
                  var index = (page - 1) * 20 + 1;
                  index <= page * 20 && index <= total;
                  index++
                )
                  SubDetailItemModel(
                    id: index,
                    title: '视频 $index',
                    cover: '',
                    duration: 10,
                  ),
              ],
            ),
          ),
        );
  }

  @override
  HiddenSubscriptionMedia hidden(Account account) {
    hiddenReads.add(account);
    return super.hidden(account);
  }

  @override
  Future<LoadingState<void>> cancel(Account account, SubItemModel item) async {
    cancellations.add((account: account, id: item.id, type: item.type));
    final result =
        await (mutation?.call() ?? Future.value(const Success(null)));
    if (result.isSuccess) {
      items.removeWhere((row) => row.type == item.type && row.id == item.id);
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LoginAccount login(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  late Account previous;
  late Account account;
  late FakeSubscriptions repository;
  late SubscriptionLibrary library;
  late ProviderContainer container;
  const list = SubscriptionQuery(owner: Object());
  const detail = SubscriptionQuery(owner: Object(), id: 7);
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Accounts.account = MemoryBox<LoginAccount>();
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.localCache.clear();
    previous = Accounts.main;
    account = login('first');
    Accounts.accountMode[AccountType.main.index] = account;
    repository = FakeSubscriptions();
    library = SubscriptionLibrary(repository);
    container = ProviderContainer(
      overrides: [subscriptionLibraryProvider.overrideWithValue(library)],
    )..listen(subscriptionOperationsProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await library.close();
    Accounts.accountMode[AccountType.main.index] = previous;
  });
  Future<SubscriptionState> keep(SubscriptionQuery query) {
    container.listen(subscriptionFeedProvider(query), (_, _) {});
    return container.read(subscriptionFeedProvider(query).future);
  }

  SubscriptionFeed feed(SubscriptionQuery query) =>
      container.read(subscriptionFeedProvider(query).notifier);
  SubscriptionState snapshot(SubscriptionQuery query) =>
      container.read(subscriptionFeedProvider(query)).value!;
  SubscriptionOperations operations() =>
      container.read(subscriptionOperationsProvider.notifier);

  test('同 UID 新凭据替换列表，迟到响应不覆盖新账号，释放后不再订阅', () async {
    final pending = Completer<LoadingState<SubData>>();
    repository.readList = (_, _) => pending.future;
    final old = keep(list);
    repository.readList = (_, _) async =>
        Success(SubData(list: [SubItemModel(id: 9, type: 21)], hasMore: false));
    final replacement = login('replacement');
    Accounts.replaceCredentials(replacement);
    final current = await container.read(subscriptionFeedProvider(list).future);
    pending.complete(
      Success(SubData(list: [SubItemModel(id: 2)], hasMore: false)),
    );
    await old;
    expect(current.account, same(replacement));
    expect(snapshot(list).items.cast<SubItemModel>().single.id, 9);
    expect(repository.requests.map((request) => request.account), [
      account,
      replacement,
    ]);
    container.dispose();
    Accounts.replaceCredentials(login('closed'));
    expect(repository.requests, hasLength(2));
    container = ProviderContainer();
  });

  test('分页按类型和 ID 去重，失败保留游标，重试串行且刷新淘汰旧分页', () async {
    repository.readList = (_, page) async => Success(
      SubData(
        list: [
          SubItemModel(id: page, type: 21),
          SubItemModel(id: 1, type: 11),
        ],
        hasMore: true,
      ),
    );
    await keep(list);
    await feed(list).loadMore();
    expect(
      snapshot(list).items
          .cast<SubItemModel>()
          .map((item) => (item.type, item.id)),
      [(21, 1), (11, 1), (21, 2)],
    );
    repository.readList = (_, _) async => const Error('失败');
    await feed(list).loadMore();
    expect(snapshot(list).next, 3);
    expect(snapshot(list).canLoadMore, isFalse);
    final pending = Completer<LoadingState<SubData>>();
    repository.readList = (_, page) => page == 1
        ? Future.value(
            Success(
              SubData(list: [SubItemModel(id: 8, type: 21)], hasMore: false),
            ),
          )
        : pending.future;
    final more = feed(list).loadMore(retry: true);
    final count = repository.requests.length;
    await feed(list).loadMore(retry: true);
    expect(repository.requests, hasLength(count));
    await feed(list).refresh();
    pending.complete(
      Success(SubData(list: [SubItemModel(id: 99, type: 21)], hasMore: false)),
    );
    await more;
    expect(snapshot(list).items.cast<SubItemModel>().single.id, 8);
  });

  test('隐藏第一页仍补读有效视频，关闭偏好并刷新恢复内容', () async {
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      true,
    );
    await repository.hidden(account).add(21, 7, {
      for (var id = 1; id <= 20; id++) (id, 2),
    });
    final state = await keep(detail);
    expect(repository.requests.map((request) => request.page), [1, 2]);
    expect(state.items.cast<SubDetailItemModel>().single.id, 21);
    expect(state.next, isNull);
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      false,
    );
    await feed(detail).refresh();
    expect(snapshot(detail).items, hasLength(20));
    expect(snapshot(detail).next, 2);
  });

  test('连续隐藏页最多补读五页，停止自动请求并保留显式继续游标', () async {
    repository.total = 200;
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      true,
    );
    await repository.hidden(account).add(21, 7, {
      for (var id = 1; id <= 120; id++) (id, 2),
    });
    final state = await keep(detail);
    expect(repository.requests.map((request) => request.page), [1, 2, 3, 4, 5]);
    expect(state.items, isEmpty);
    expect(state.next, 6);
    expect(state.canLoadMore, isFalse);
    await feed(detail).loadMore();
    expect(repository.requests, hasLength(5));
    await feed(detail).loadMore(retry: true);
    expect(repository.requests.map((request) => request.page), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(snapshot(detail).items.cast<SubDetailItemModel>().first.id, 121);
  });

  test('隐藏页补读失败进入可重试错误，刷新从头读取', () async {
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      true,
    );
    await repository.hidden(account).add(21, 7, {
      for (var id = 1; id <= 20; id++) (id, 2),
    });
    repository.readDetail = (_, id, page) async => page == 2
        ? const Error('网络错误')
        : Success(
            SubDetailData(
              info: SubItemModel(id: id, mediaCount: 21),
              medias: [
                for (var index = 1; index <= 20; index++)
                  SubDetailItemModel(id: index),
              ],
            ),
          );
    await expectLater(keep(detail), throwsA(isA<Error>()));
    expect(repository.requests.map((request) => request.page), [1, 2]);
    expect(container.read(subscriptionFeedProvider(detail)).hasError, isTrue);
    repository.readDetail = null;
    await feed(detail).refresh();
    expect(snapshot(detail).items.cast<SubDetailItemModel>().single.id, 21);
  });

  test('切号和释放后迟到详情不读隐藏缓存，也不补页', () async {
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      true,
    );
    final pending = Completer<LoadingState<SubDetailData>>();
    repository.readDetail = (_, _, _) => pending.future;
    final old = keep(detail);
    repository.readDetail = null;
    Accounts.replaceCredentials(login('new'));
    await container.read(subscriptionFeedProvider(detail).future);
    repository.hiddenReads.clear();
    pending.complete(
      Success(
        SubDetailData(
          info: SubItemModel(mediaCount: 100),
          medias: List.generate(20, (id) => SubDetailItemModel(id: id)),
        ),
      ),
    );
    await old;
    expect(repository.hiddenReads, isEmpty);
    expect(repository.requests, hasLength(2));
    final released = Completer<LoadingState<SubDetailData>>();
    repository.readDetail = (_, _, _) => released.future;
    final refresh = feed(detail).refresh();
    unawaited(refresh.catchError((_) {}));
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    released.complete(
      Success(
        SubDetailData(
          info: SubItemModel(mediaCount: 100),
          medias: List.generate(20, (id) => SubDetailItemModel(id: id)),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.hiddenReads, isEmpty);
    expect(repository.requests, hasLength(3));
    container = ProviderContainer();
  });

  test('成功取消统一失效所有页面，失败和待确认保留来源及隐藏记录', () async {
    final owner = Object();
    final second = SubscriptionQuery(owner: owner);
    await keep(list);
    await keep(second);
    await keep(detail);
    await repository.hidden(account).add(21, 1, {(9, 2)});
    final source = snapshot(list),
        item = snapshot(list).items.single as SubItemModel;
    for (final result in [const Error('拒绝'), const UnknownResult()]) {
      repository.mutation = () async => result;
      expect(
        await operations().cancel(
          source,
          item,
          isCurrent: () => feed(list).canCancel(source, item),
        ),
        same(result),
      );
      expect(repository.requests, hasLength(3));
      expect(feed(list).isCurrent(source), isTrue);
      expect(repository.hidden(account).read(21, 1), {'2:9'});
    }
    repository.mutation = null;
    expect(
      (await operations().cancel(
        source,
        item,
        isCurrent: () => feed(list).canCancel(source, item),
      )).isSuccess,
      isTrue,
    );
    await container.read(subscriptionFeedProvider(list).future);
    await container.read(subscriptionFeedProvider(second).future);
    await container.read(subscriptionFeedProvider(detail).future);
    expect(repository.requests, hasLength(6));
    expect(snapshot(list).items, isEmpty);
    expect(repository.hidden(account).read(21, 1), isEmpty);
    expect(feed(list).isCurrent(source), isFalse);
  });

  test('刷新后旧弹窗来源不能取消订阅', () async {
    final source = await keep(list),
        item = snapshot(list).items.single as SubItemModel;
    await feed(list).refresh();
    final result = await operations().cancel(
      source,
      item,
      isCurrent: () => feed(list).canCancel(source, item),
    );
    expect(result, isA<Error>());
    expect(repository.cancellations, isEmpty);
  });

  test('清理与取消共用写入锁，待确认单独汇总，结束后刷新列表', () async {
    final source = await keep(list),
        item = snapshot(list).items.single as SubItemModel;
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final clean = operations().clean(
      account,
      hideInvalid: true,
      isCurrent: () => true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(subscriptionOperationsProvider).cleaning, isTrue);
    expect(
      await operations().cancel(source, item, isCurrent: () => true),
      isA<Error>(),
    );
    expect(repository.cancellations, hasLength(1));
    pending.complete(const UnknownResult());
    final report = (await clean).data;
    expect(report.result.pending, 1);
    expect(report.result.failed, 0);
    expect(report.message, contains('1 个取消结果待确认'));
    await container.read(subscriptionFeedProvider(list).future);
    expect(repository.requests, hasLength(3));
    expect(container.read(subscriptionOperationsProvider).busy, isFalse);
  });

  test('页面释放或换凭据中止全量扫描，旧操作不继续提交', () async {
    await keep(list);
    final pending = Completer<LoadingState<SubData>>();
    repository.readList = (_, _) => pending.future;
    var mounted = true;
    final clean = operations().clean(
      account,
      hideInvalid: true,
      isCurrent: () => mounted,
    );
    mounted = false;
    pending.complete(
      Success(
        SubData(list: [SubItemModel(id: 1, type: 21, state: 1)], hasMore: true),
      ),
    );
    expect(await clean, isA<Error>());
    expect(repository.cancellations, isEmpty);
    expect(repository.requests, hasLength(2));
    expect(container.read(subscriptionOperationsProvider).busy, isFalse);
    expect(feed(list).isCurrent(snapshot(list)), isTrue);
  });

  test('缺失列表分页信息和无效合集 ID 返回错误', () async {
    repository.readList = (_, _) async => Success(SubData(list: []));
    await expectLater(keep(list), throwsA(isA<Error>()));
    await expectLater(
      keep(const SubscriptionQuery(owner: Object(), id: 0)),
      throwsA(isA<Error>()),
    );
    expect(repository.requests, hasLength(1));
  });

  testWidgets('订阅页面按 Riverpod 快照显示，退出后释放查询', (tester) async {
    repository.items = [];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SubPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的订阅'), findsOneWidget);
    expect(find.text('清除失效内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final count = repository.requests.length;
    Accounts.replaceCredentials(login('closed'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.requests, hasLength(count));
    container.dispose();
    container = ProviderContainer();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('订阅详情刷新保留合集标题，切号时隐藏旧合集', (tester) async {
    repository.total = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SubDetailPage(id: 7)),
      ),
    );
    await tester.pumpAndSettle();
    void expectContent(String title) {
      expect(find.text('视频 1'), findsOneWidget);
      expect(find.text(title), findsWidgets);
    }

    expectContent('合集 7');
    var pending = Completer<LoadingState<SubDetailData>>();
    repository.readDetail = (_, _, _) => pending.future;
    final operation = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expectContent('合集 7');
    pending.complete(const Error('离线'));
    await operation;
    await tester.pumpAndSettle();
    expectContent('合集 7');
    expect(find.textContaining('离线'), findsOneWidget);
    repository.readDetail = (_, _, _) async => Success(
      SubDetailData(
        info: SubItemModel(id: 7, title: '新合集', mediaCount: 1),
        medias: [
          SubDetailItemModel(id: 2, title: '视频 2', cover: '', duration: 10),
        ],
      ),
    );
    await tester.tap(find.textContaining('离线'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.page, 1);
    expect(find.text('视频 1'), findsNothing);
    expect(find.text('视频 2'), findsOneWidget);
    expect(find.textContaining('离线'), findsNothing);
    expect(find.text('新合集'), findsWidgets);

    pending = Completer();
    repository.readDetail = (_, _, _) => pending.future;
    Accounts.replaceCredentials(login('replacement'));
    await tester.pump();
    expect(find.text('新合集'), findsNothing);
    expect(find.text('视频 2'), findsNothing);
    pending.complete(const Error('新账号离线'));
    await tester.pumpAndSettle();
    expect(find.text('新合集'), findsNothing);
    expect(find.text('视频 2'), findsNothing);
    expect(find.textContaining('新账号离线'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    container = ProviderContainer();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
