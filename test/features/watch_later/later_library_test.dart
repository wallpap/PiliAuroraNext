import 'package:pili_aurora_next/features/content_library/application/library_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/watch_later/presentation/later_page.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/owner.dart';

import '../../support/memory_box.dart';

import 'package:pili_aurora_next/utils/storage.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/features/watch_later/data/later_repository.dart';
import 'package:pili_aurora_next/features/watch_later/domain/data.dart';
import 'package:pili_aurora_next/features/watch_later/domain/list.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class FakeLaterRepository extends LaterRepository {
  Future<LaterData> Function(Account, int, int, String, bool)? read;
  Future<LoadingState<void>> Function()? mutation;
  final requests =
      <({Account account, int page, int viewed, String keyword, bool asc})>[];
  final removed = <List<int>>[];
  @override
  Future<LaterData> page(
    Account account, {
    required int page,
    required int viewed,
    required String keyword,
    required bool asc,
  }) async {
    requests.add((
      account: account,
      page: page,
      viewed: viewed,
      keyword: keyword,
      asc: asc,
    ));
    return read != null
        ? read!(account, page, viewed, keyword, asc)
        : LaterData(
            count: 40,
            list: [
              for (var i = (page - 1) * 20; i < page * 20; i++)
                LaterItemModel(aid: i + 1),
            ],
          );
  }

  @override
  Future<LoadingState<void>> remove(Account account, Iterable<int> aids) {
    removed.add(aids.toList());
    return mutation?.call() ?? Future.value(const Success(null));
  }

  @override
  Future<LoadingState<void>> clear(Account account, int? type) =>
      mutation?.call() ?? Future.value(const Success(null));
  @override
  Future<LoadingState<void>> add(
    Account account, {
    String? bvid,
    Object? aid,
  }) => mutation?.call() ?? Future.value(const Success(null));
}

class FakePlayAll extends PlayAllPreference {
  @override
  bool build() => false;
}

class TestMainAccount extends MainAccountNotifier {
  @override
  Account build() => Accounts.main;
  void replace(Account account) {
    Accounts.accountMode[AccountType.main.index] = account;
    state = account;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.localCache = MemoryBox();
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
  });
  Account account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  late FakeLaterRepository repository;
  late LaterLibrary library;
  late ProviderContainer container;
  final query = (owner: Object(), viewed: 0, keyword: '', asc: false);
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = account();
    repository = FakeLaterRepository();
    library = LaterLibrary(repository);
    container = ProviderContainer(
      overrides: [
        laterLibraryProvider.overrideWithValue(library),
        playAllProvider.overrideWith(FakePlayAll.new),
        mainAccountProvider.overrideWith(TestMainAccount.new),
      ],
    )..listen(laterFeedProvider(query), (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await library.close();
  });

  test('分页串行、按 aid 去重，失败保留游标并显式重试', () async {
    final provider = laterFeedProvider(query);
    final first = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final pending = Completer<LaterData>();
    repository.read = (_, _, _, _, _) => pending.future;
    final more = notifier.loadMore();
    await notifier.loadMore();
    expect(repository.requests.map((r) => r.page), [1, 2]);
    pending.completeError(const Error('网络失败'));
    await more;
    expect(container.read(provider).value!.items, first.items);
    expect(container.read(provider).value!.next, 2);
    await notifier.loadMore();
    expect(repository.requests, hasLength(2));
    repository.read = (_, _, _, _, _) async => LaterData(
      count: 40,
      list: [LaterItemModel(aid: 20), LaterItemModel(aid: 21)],
    );
    await notifier.loadMore(retry: true);
    expect(
      container.read(provider).value!.items.map((item) => item.aid),
      orderedEquals(List.generate(21, (i) => i + 1)),
    );
    expect(container.read(provider).value!.next, isNull);
  });

  test('刷新替换来源后，旧分页不回写新列表', () async {
    final provider = laterFeedProvider(query);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final pending = Completer<LaterData>();
    repository.read = (_, page, _, _, _) => page == 2
        ? pending.future
        : Future.value(LaterData(count: 1, list: [LaterItemModel(aid: 90)]));
    final more = notifier.loadMore();
    await notifier.refresh();
    pending.complete(LaterData(count: 40, list: [LaterItemModel(aid: 22)]));
    await more;
    expect(container.read(provider).value!.items.single.aid, 90);
  });

  test('同 UID 新凭据重建查询并拒绝旧快照写入', () async {
    final provider = laterFeedProvider(query);
    final old = await container.read(provider.future);
    (container.read(mainAccountProvider.notifier) as TestMainAccount).replace(
      account('replacement'),
    );
    await container.read(provider.future);
    expect(repository.requests.map((request) => request.account.csrf), [
      'fixture',
      'replacement',
    ]);
    expect(
      await container.read(provider.notifier).remove(old, [old.items.first]),
      isA<Error>(),
    );
    expect(repository.removed, isEmpty);
  });

  test('成功写入使不同标签与搜索同时失效', () async {
    final search = laterFeedProvider((
      owner: Object(),
      viewed: 2,
      keyword: 'test',
      asc: true,
    ));
    container.listen(search, (_, _) {});
    final first = await container.read(laterFeedProvider(query).future);
    await container.read(search.future);
    repository.requests.clear();
    repository.read = (_, _, _, keyword, _) async => LaterData(
      count: 1,
      list: [LaterItemModel(aid: keyword.isEmpty ? 2 : 3)],
    );
    expect(await library.remove([1]), isA<Success>());
    final current = await container.read(laterFeedProvider(query).future);
    final newSearch = await container.read(search.future);
    expect(current.items.single.aid, 2);
    expect(newSearch.items.single.aid, 3);
    expect(
      repository.requests.map(
        (request) =>
            (request.page, request.viewed, request.keyword, request.asc),
      ),
      unorderedEquals([(1, 0, '', false), (1, 2, 'test', true)]),
    );
    expect(
      await container.read(laterFeedProvider(query).notifier).remove(first, [
        first.items.first,
      ]),
      isA<Error>(),
    );
    expect(repository.removed, [
      [1],
    ]);
  });

  test('删除、清空共用写锁，待确认保留查询并允许核对后重试', () async {
    final provider = laterFeedProvider(query);
    final first = await container.read(provider.future);
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final remove = library.remove([1]);
    expect(await library.clear(null), isA<Error>());
    expect(repository.removed, hasLength(1));
    pending.complete(const UnknownResult());
    expect(await remove, isA<UnknownResult>());
    expect(repository.requests, hasLength(1));
    expect(
      container.read(provider).value!.items.map((item) => item.aid),
      first.items.map((item) => item.aid),
    );
    repository.mutation = () async => const Success(null);
    expect(await library.remove([1]), isA<Success>());
    await container.read(provider.future);
    expect(repository.removed, hasLength(2));
  });

  test('写入异常保留原因且释放锁，迟到成功不刷新新账号', () async {
    await container.read(laterFeedProvider(query).future);
    final cause = StateError('fixture');
    repository.mutation = () => Future.error(cause);
    final failed = await library.remove([1]);
    expect(failed, isA<UnknownResult>());
    expect((failed as Error).cause, same(cause));
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final old = library.remove([1]);
    (container.read(mainAccountProvider.notifier) as TestMainAccount).replace(
      account(),
    );
    await container.read(laterFeedProvider(query).future);
    pending.complete(const Success(null));
    expect(await old, isA<Success>());
    await container.read(laterFeedProvider(query).future);
    expect(repository.requests, hasLength(2));
  });

  test('释放查询后迟到分页被消费，Module 仍能供其他入口写入', () async {
    await container.read(laterFeedProvider(query).future);
    final pending = Completer<LaterData>();
    repository.read = (_, _, _, _, _) => pending.future;
    final more = container.read(laterFeedProvider(query).notifier).loadMore();
    container.dispose();
    container = ProviderContainer();
    pending.completeError(const Error('迟到失败'));
    await more;
    repository.mutation = () async => const Success(null);
    expect(await library.remove([1]), isA<Success>());
  });
  testWidgets('页面选择保留在 Widget，刷新后清除旧选择', (tester) async {
    repository.read = (_, _, _, _, _) async => LaterData(
      count: 1,
      list: [
        LaterItemModel(
          aid: 42,
          cid: 43,
          title: 'fixture video',
          pic: '',
          duration: 120,
          owner: Owner(name: 'fixture author'),
        ),
      ],
    );
    await container.refresh(laterFeedProvider(query).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: LaterPanel(query: query)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('fixture video'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    final snapshot = container.read(laterFeedProvider(query)).value!;
    final pending = container.read(laterFeedProvider(query).notifier).refresh();
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('已选 1'), findsNothing);
    expect(snapshot.items.single.aid, 42);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('待确认删除保留选择，成功后关闭自己的弹窗并刷新', (tester) async {
    repository.mutation = () async => const UnknownResult();
    await Future<void>.value();
    repository.read = (_, _, _, _, _) async => LaterData(
      count: 1,
      list: [
        LaterItemModel(
          aid: 42,
          cid: 43,
          title: 'fixture video',
          pic: '',
          duration: 120,
          owner: Owner(name: 'fixture author'),
        ),
      ],
    );
    await container.refresh(laterFeedProvider(query).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: LaterPanel(query: query)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('fixture video'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);
    expect(find.text('已选 1'), findsOneWidget);
    repository.mutation = () async => const Success(null);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('移除所选稍后再看？'), findsNothing);
    expect(find.text('已选 1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
