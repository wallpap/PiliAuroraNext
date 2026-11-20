import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_state.dart';
import 'package:pili_aurora_next/features/content_discovery/data/recommendation_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/models/model_owner.dart';
import 'package:pili_aurora_next/models/model_rec_video_item.dart';
import 'package:pili_aurora_next/models/model_video.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

class _Video extends BaseRcmdVideoItemModel {
  _Video(int id) {
    aid = id;
    title = '视频 $id';
    owner = Owner(mid: 8, name: '作者');
    stat = Stat.fromJson({});
  }
}

typedef _Call = ({
  Account account,
  bool app,
  int index,
  int size,
  CancelToken token,
  Completer<LoadingState<List<BaseRcmdVideoItemModel>>> result,
});

class _Repository extends RecommendationRepository {
  final calls = <_Call>[];
  @override
  Future<LoadingState<List<BaseRcmdVideoItemModel>>> page({
    required Account account,
    required bool app,
    required int index,
    required int pageSize,
    required CancelToken cancelToken,
  }) {
    final result = Completer<LoadingState<List<BaseRcmdVideoItemModel>>>();
    calls.add((
      account: account,
      app: app,
      index: index,
      size: pageSize,
      token: cancelToken,
      result: result,
    ));
    return result.future;
  }
}

class _Filter extends DiscoveryFilter {
  @override
  Future<void>? prepare() => null;
}

LoginAccount _login(int mid, [String csrf = 'fixture']) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
  null,
  null,
)..activated = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Repository repository;
  late MemoryBox<LoginAccount> accounts;
  late LoginAccount main, recommend;
  late ProviderSubscription<RecommendationState> subscription;

  setUpAll(() async {
    GStorage.setting = await Hive.openBox<dynamic>(
      'recommendation-lifecycle',
      bytes: Uint8List(0),
    );
    GStorage.localCache = MemoryBox<dynamic>();
    GStorage.video = MemoryBox<dynamic>();
    GStorage.userInfo = MemoryBox<UserInfoData>();
    Accounts.account = accounts = MemoryBox<LoginAccount>();
    AnonymousAccount().activated = true;
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.setting.putAll({
      SettingBoxKey.filterBlockedAuthors: false,
      SettingBoxKey.enableSearchWord: false,
      SettingBoxKey.hideTopBar: false,
    });
    accounts.data.clear();
    for (final role in AccountType.values) {
      Accounts.accountMode[role.index] = AnonymousAccount();
    }
    main = _login(100)..type.add(AccountType.main);
    recommend = _login(200)..type.add(AccountType.recommend);
    Accounts.accountMode[AccountType.main.index] = main;
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    accounts.data.addAll({'100': main, '200': recommend});
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        recommendationRepositoryProvider.overrideWithValue(repository),
        discoveryFilterProvider.overrideWithValue(_Filter()),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    for (final call in repository.calls) {
      if (!call.result.isCompleted) call.result.complete(const Success([]));
    }
    Get.reset();
  });
  tearDownAll(Hive.close);

  RecommendationFeed watch() {
    subscription = container.listen(recommendationFeedProvider, (_, _) {});
    return container.read(recommendationFeedProvider.notifier);
  }

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  Future<void> complete(_Call call, List<BaseRcmdVideoItemModel> items) async {
    call.result.complete(Success(items));
    await settle();
  }

  RecommendationState snapshot() => container.read(recommendationFeedProvider);

  for (final role in [AccountType.main, AccountType.recommend]) {
    test('真实${role.name}同 UID 换凭据淘汰旧查询，并固定推荐请求账号', () async {
      final feed = watch()
        ..updateViewport(itemCount: 1, columns: 1, active: true);
      final old = repository.calls.single;
      final next = _login(role == AccountType.main ? 100 : 200, 'renewed');
      Accounts.replaceCredentials(next);
      await settle();
      expect(old.token.isCancelled, isTrue);
      expect(repository.calls, hasLength(2));
      final current = repository.calls.last;
      expect(
        current.account,
        same(role == AccountType.main ? recommend : next),
      );
      expect(current.index, 0);
      expect(snapshot().loading, isA<Loading>());
      await complete(old, [_Video(1)]);
      expect(snapshot().loading, isA<Loading>());
      expect(feed.isLoading, isTrue);
      await complete(current, [_Video(2)]);
      expect(snapshot().loading.data.single.aid, 2);
      expect(snapshot().loadingMore, isFalse);
      expect(
        () => snapshot().loading.data.add(_Video(3)),
        throwsUnsupportedError,
      );
    });
  }

  test('共用账号换凭据时合并角色通知，只启动一次新查询', () async {
    Accounts.accountMode[AccountType.recommend.index] = main;
    watch().updateViewport(itemCount: 1, columns: 1, active: true);
    final next = _login(100, 'renewed');
    Accounts.replaceCredentials(next);
    await settle();
    expect(repository.calls.map((call) => call.index), [0, 0]);
    expect(repository.calls.last.account, same(next));
  });

  test('后台换号立即隐藏旧内容，返回后按原视口重新读取', () async {
    final feed = watch()
      ..updateViewport(itemCount: 1, columns: 1, active: true);
    await complete(repository.calls.single, [_Video(1)]);
    feed.updateViewport(itemCount: 1, columns: 1, active: false);
    Accounts.replaceCredentials(_login(200, 'renewed'));
    await settle();
    expect(snapshot().loading, isA<Loading>());
    expect(snapshot().historyStart, isNull);
    expect(repository.calls, hasLength(1));
    feed.updateViewport(itemCount: 1, columns: 1, active: true);
    await complete(repository.calls.last, [_Video(2)]);
    expect(snapshot().loading.data.single.aid, 2);
    expect(snapshot().historyStart, isNull);
  });

  test('并存的推荐页由活动视口调度，离页后交接给仍可见的页面', () async {
    final home = Object();
    final preview = Object();
    final feed = watch()
      ..updateViewport(owner: home, itemCount: 2, columns: 1, active: true)
      ..updateViewport(owner: preview, itemCount: 3, columns: 2, active: false);

    await complete(repository.calls.single, [_Video(1)]);
    expect(repository.calls.map((call) => call.index), [0, 1]);
    feed.updateViewport(owner: preview, itemCount: 3, columns: 2, active: true);
    await complete(repository.calls.last, [_Video(2)]);
    expect(repository.calls, hasLength(2));

    feed.removeViewport(home);
    await settle();
    expect(repository.calls.map((call) => call.index), [0, 1, 2]);

    feed.removeViewport(preview);
    await complete(repository.calls.last, []);
    expect(repository.calls, hasLength(3));
    expect(snapshot().loading.data.map((item) => item.aid), [1, 2]);
  });

  test('Hive 来源变更取消 App 查询，从 Web 首页按视口重读', () async {
    watch().updateViewport(itemCount: 40, columns: 8, active: true);
    final old = repository.calls.single;
    await GStorage.setting.put(SettingBoxKey.appRcmd, false);
    await settle();
    final current = repository.calls.last;
    expect(repository.calls, hasLength(2));
    expect(old.token.isCancelled, isTrue);
    expect(current.app, isFalse);
    expect(current.index, 0);
    expect(current.size, 40);
    await complete(old, [_Video(1)]);
    expect(snapshot().loading, isA<Loading>());
    await complete(current, List.generate(40, (i) => _Video(i + 2)));
    expect(snapshot().loading.data, hasLength(40));
    expect(snapshot().historyStart, isNull);
  });

  test('Hive 历史提示与保留偏好同步生效，关闭后分页不恢复提示', () async {
    final feed = watch()
      ..updateViewport(itemCount: 1, columns: 1, active: true);
    await complete(repository.calls.last, [_Video(1)]);
    var refresh = feed.onRefresh();
    await complete(repository.calls.last, [_Video(2)]);
    await refresh;
    expect(snapshot().historyStart, 1);
    final calls = repository.calls.length;
    await GStorage.setting.put(SettingBoxKey.savedRcmdTip, false);
    await settle();
    expect(snapshot().historyStart, isNull);
    await GStorage.setting.put(SettingBoxKey.savedRcmdTip, true);
    await settle();
    expect(snapshot().historyStart, 1);
    await GStorage.setting.put(SettingBoxKey.enableSaveLastData, false);
    await settle();
    expect(snapshot().historyStart, isNull);
    expect(repository.calls, hasLength(calls));
    final more = feed.onLoadMore();
    await complete(repository.calls.last, [_Video(3), _Video(4)]);
    await more;
    expect(snapshot().historyStart, isNull);
    expect(snapshot().loading.data.map((item) => item.aid), [2, 1, 3, 4]);
    refresh = feed.onRefresh();
    await complete(repository.calls.last, [_Video(5)]);
    await refresh;
    expect(snapshot().loading.data.single.aid, 5);
  });

  test('最后订阅释放取消请求与角色/偏好订阅，迟到响应不能发布', () async {
    watch().updateViewport(itemCount: 1, columns: 1, active: true);
    final old = repository.calls.single;
    subscription.close();
    await settle();
    expect(old.token.isCancelled, isTrue);
    expect(container.exists(recommendationFeedProvider), isFalse);
    expect(container.exists(recommendationPreferencesProvider), isFalse);
    expect(container.exists(mainAccountProvider), isFalse);
    expect(container.exists(recommendAccountProvider), isFalse);
    Accounts.replaceCredentials(_login(200, 'renewed'));
    await GStorage.setting.put(SettingBoxKey.appRcmd, false);
    old.result.complete(Success([_Video(1)]));
    await settle();
    expect(repository.calls, hasLength(1));
    expect(container.exists(recommendationFeedProvider), isFalse);
  });

  test('provider 失效重建后拒绝旧运行的迟到结果', () async {
    final feed = watch()
      ..updateViewport(itemCount: 1, columns: 1, active: true);
    final old = repository.calls.single;
    container.invalidate(recommendationFeedProvider);
    final current = container.read(recommendationFeedProvider.notifier);
    expect(old.token.isCancelled, isTrue);
    expect(snapshot().loading, isA<Loading>());
    current.updateViewport(itemCount: 1, columns: 1, active: true);
    await complete(old, [_Video(1)]);
    expect(snapshot().loading, isA<Loading>());
    expect(current.isLoading, isTrue);
    await complete(repository.calls.last, [_Video(2)]);
    expect(snapshot().loading.data.single.aid, 2);
    expect(feed, same(current));
  });

  testWidgets('首页壳通过页面句柄刷新，卸载释放注册、滚动与查询', (tester) async {
    RecommendationPageHandle? registered;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RecommendationPage(
              register: (handle) {
                registered = handle;
                return () => registered = null;
              },
            ),
          ),
        ),
      ),
    );
    final handle = registered!;
    expect(handle.scrollController.hasClients, isTrue);
    final refresh = handle.onRefresh();
    expect(repository.calls.first.token.isCancelled, isTrue);
    final target = container
        .read(recommendationFeedProvider.notifier)
        .viewportItems;
    repository.calls.last.result.complete(
      Success(List.generate(target, _Video.new)),
    );
    await tester.pump();
    await refresh;
    expect(handle.snapshot.loading.data, hasLength(target));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    expect(registered, isNull);
    await tester.pump();
    expect(container.exists(recommendationFeedProvider), isFalse);
    expect(
      () => handle.scrollController.addListener(() {}),
      throwsFlutterError,
    );
    container.dispose();
  });
}
