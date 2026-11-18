import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/history/data/history_repository.dart';
import 'package:pili_aurora_next/features/history/domain/data.dart';
import 'package:pili_aurora_next/features/history/domain/history.dart';
import 'package:pili_aurora_next/features/history/domain/list.dart';
import 'package:pili_aurora_next/features/history/domain/tab.dart';
import 'package:pili_aurora_next/features/history/presentation/history_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

import '../../support/memory_box.dart';

HistoryItemModel item(int id, {String business = 'archive'}) =>
    HistoryItemModel(
      kid: id,
      history: History(oid: id, business: business),
      viewAt: id * 10,
      title: '记录 $id',
      cover: '',
      videos: 1,
      duration: 100,
      progress: 20,
    );

class FakeHistoryRepository extends HistoryRepository {
  Future<HistoryData> Function(Object?)? read;
  Future<LoadingState<bool>> Function()? readStatus;
  Future<LoadingState<void>> Function()? mutation;
  final requests =
      <
        ({
          Account account,
          String type,
          String keyword,
          bool search,
          Object? cursor,
        })
      >[];
  final removed = <List<String>>[];
  final cached = <bool>[];
  Object? cacheFailure;
  int pauses = 0, clears = 0;
  @override
  Future<HistoryData> page(
    Account account, {
    required String type,
    required String keyword,
    required bool search,
    Object? cursor,
  }) {
    requests.add((
      account: account,
      type: type,
      keyword: keyword,
      search: search,
      cursor: cursor,
    ));
    return read?.call(cursor) ??
        Future.value(
          HistoryData(
            list: [item(1)],
            tab: [HistoryTab(type: 'archive', name: '视频')],
          ),
        );
  }

  @override
  Future<LoadingState<bool>> status(Account account) =>
      readStatus?.call() ?? Future.value(const Success(false));
  @override
  Future<LoadingState<void>> pause(Account account, bool paused) {
    pauses++;
    return mutation?.call() ?? Future.value(const Success(null));
  }

  @override
  Future<LoadingState<void>> clear(Account account) {
    clears++;
    return mutation?.call() ?? Future.value(const Success(null));
  }

  @override
  Future<LoadingState<void>> remove(Account account, List<String> ids) {
    removed.add(ids);
    return mutation?.call() ?? Future.value(const Success(null));
  }

  @override
  Future<void> cachePause(bool paused) async {
    if (cacheFailure != null) throw cacheFailure!;
    cached.add(paused);
    await super.cachePause(paused);
  }
}

class TestHistoryAccount extends HistoryAccountNotifier {
  @override
  Account build() => Accounts.history;
  void replace(Account account) {
    Accounts.accountMode[AccountType.heartbeat.index] = account;
    state = account;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LoginAccount account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture'}),
    null,
    null,
  );
  late ProviderContainer container;
  late FakeHistoryRepository repository;
  late HistoryLibrary library;
  final query = (owner: Object(), type: 'all', keyword: '', search: false);
  setUpAll(() {
    GStorage.localCache = MemoryBox();
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
  });
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = account(1);
    Accounts.accountMode[AccountType.heartbeat.index] = account(2);
    repository = FakeHistoryRepository();
    library = HistoryLibrary(repository);
    container = ProviderContainer(
      overrides: [
        historyLibraryProvider.overrideWithValue(library),
        historyAccountProvider.overrideWith(TestHistoryAccount.new),
      ],
    )..listen(historyFeedProvider(query), (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await library.close();
  });
  test('列表沿历史账号查询，游标重复停止并保留分类', () async {
    final provider = historyFeedProvider(query);
    final first = await container.read(provider.future);
    expect(first.account.mid, 2);
    repository.read = (_) async => HistoryData(
      list: [
        item(1),
        item(1, business: 'live'),
      ],
    );
    await container.read(provider.notifier).loadMore();
    final current = container.read(provider).value!;
    expect(current.items, hasLength(2));
    expect(current.next, isNull);
    expect(current.metadata.single.type, 'archive');
    expect(repository.requests.last.cursor, (1, 10));
  });
  test('分页失败保留游标，刷新后丢弃旧分页', () async {
    final provider = historyFeedProvider(query);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    repository.read = (_) => Future.error(const Error('失败'));
    await notifier.loadMore();
    expect(container.read(provider).value!.next, (1, 10));
    final pending = Completer<HistoryData>();
    repository.read = (cursor) => cursor == null
        ? Future.value(HistoryData(list: [item(9)]))
        : pending.future;
    final more = notifier.loadMore(retry: true);
    await notifier.refresh();
    pending.complete(HistoryData(list: [item(2)]));
    await more;
    expect(container.read(provider).value!.items.single.kid, 9);
  });
  test('搜索以提交关键词和页码隔离，删除使列表和搜索同时重读', () async {
    final search = historyFeedProvider((
      owner: Object(),
      type: 'all',
      keyword: 'test',
      search: true,
    ));
    container.listen(search, (_, _) {});
    final old = await container.read(search.future);
    await container.read(historyFeedProvider(query).future);
    expect(old.next, isNull);
    expect(repository.requests.last.search, isTrue);
    expect(repository.requests.last.keyword, 'test');
    expect(
      await container.read(search.notifier).remove(old, old.items),
      isA<Success>(),
    );
    final current = await container.read(search.future);
    await container.read(historyFeedProvider(query).future);
    expect(current.source, isNot(same(old.source)));
    expect(repository.removed.single, ['archive_1']);
  });
  test('删除和清空互斥，待确认不失效；同 UID 换凭据拒绝旧快照', () async {
    final provider = historyFeedProvider(query);
    final first = await container.read(provider.future);
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final remove = container.read(provider.notifier).remove(first, first.items);
    expect(await library.clear(first.account), isA<Error>());
    expect(repository.clears, 0);
    pending.complete(const UnknownResult());
    await remove;
    expect(container.read(provider).value!.source, same(first.source));
    (container.read(historyAccountProvider.notifier) as TestHistoryAccount)
        .replace(account(2));
    await container.read(provider.future);
    expect(
      await container.read(provider.notifier).remove(first, first.items),
      isA<Error>(),
    );
    expect(repository.removed, hasLength(1));
  });
  test('暂停以确认写入为准，旧查询不会覆盖新状态和缓存', () async {
    final old = Completer<LoadingState<bool>>();
    repository.readStatus = () => old.future;
    final paused = <bool>[];
    final sub = library.pauseChanges.listen(
      (value) => paused.add(value.paused),
    );
    final query = library.status(Accounts.history);
    expect(await library.pause(Accounts.history, true), isA<Success>());
    old.complete(const Success(false));
    await query;
    expect(repository.cached, [true]);
    expect(paused, [true]);
    await sub.cancel();
  });
  for (final paused in [true, false]) {
    test('保存历史暂停状态 $paused 时，状态查询不能阻止更新播放偏好', () async {
      await GStorage.localCache.put(LocalCacheKey.historyPause, !paused);
      final pending = Completer<LoadingState<void>>();
      repository
        ..mutation = () =>
            pending.future..readStatus = () => fail('保存期间不应读取远端状态');
      final current = Accounts.history;
      final save = library.pause(current, paused);
      expect(repository.pauses, 1);
      expect(await library.status(current), isA<Error>());
      pending.complete(const Success(null));
      expect(await save, isA<Success>());
      expect(Pref.historyPause, paused);
    });
  }
  test('旧凭据保存未结束时，新凭据仍能读取并缓存历史状态', () async {
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final save = library.pause(Accounts.history, true);
    final replacement = account(2);
    (container.read(historyAccountProvider.notifier) as TestHistoryAccount)
        .replace(replacement);
    expect(await library.status(replacement), isA<Success>());
    pending.complete(const Success(null));
    expect(await save, isA<Success>());
    expect(repository.cached, [false]);
    expect(Pref.historyPause, isFalse);
  });
  test('暂停 provider 的旧初始化不覆盖写入回执', () async {
    final old = Completer<LoadingState<bool>>();
    repository.readStatus = () => old.future;
    container
      ..listen(historyPauseProvider, (_, _) {})
      ..read(historyPauseProvider);
    expect(
      await container.read(historyPauseProvider.notifier).set(true),
      isA<Success>(),
    );
    old.complete(const Success(false));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(historyPauseProvider).value, isTrue);
    expect(container.read(historyPauseProvider).hasError, isFalse);
  });
  test('暂停缓存失败保留远端确认值；后台状态缓存失败沿 Future 交付', () async {
    container.listen(historyPauseProvider, (_, _) {});
    await container.read(historyPauseProvider.future);
    final failure = StateError('cache');
    repository.cacheFailure = failure;
    expect(
      await container.read(historyPauseProvider.notifier).set(true),
      isA<Error>(),
    );
    expect(container.read(historyPauseProvider).value, isTrue);
    await expectLater(library.status(Accounts.history), throwsA(same(failure)));
  });
  test('实际账号通知覆盖心跳凭据替换及匿名回退', () {
    final actual = ProviderContainer();
    addTearDown(actual.dispose);
    final seen = <Account>[];
    actual.listen(historyAccountProvider, (_, next) => seen.add(next));
    expect(actual.read(historyAccountProvider).mid, 2);
    final replacement = account(2);
    Accounts.replaceCredentials(replacement);
    expect(actual.read(historyAccountProvider), same(replacement));
    Accounts.accountMode[AccountType.heartbeat.index] = AnonymousAccount();
    final main = account(1);
    Accounts.replaceCredentials(main);
    expect(actual.read(historyAccountProvider), same(main));
    expect(seen, [replacement, main]);
  });
  testWidgets('历史页面选择独立，确认删除成功刷新并清除选择', (tester) async {
    await container.refresh(historyFeedProvider(query).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: HistoryPanel(query: query)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('记录 1'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.removed.single, ['archive_1']);
    expect(find.text('已选 1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
