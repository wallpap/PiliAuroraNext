import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart'
    as refresh;
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/data/hot_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/data/curated_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/data/pgc_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/data/rank_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/weekly_catalog.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_result/list.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_timeline/result.dart';
import 'package:pili_aurora_next/models/remote/popular/popular_series_one/config.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/pages/hot/view.dart';
import 'package:pili_aurora_next/pages/pgc/view.dart';
import 'package:pili_aurora_next/pages/popular_series/view.dart';
import 'package:pili_aurora_next/pages/rank/view.dart';
import 'package:pili_aurora_next/pages/rank/zone/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

class _Hot extends HotRepository {
  int requests = 0;
  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, void>>> fetch(
    Account account,
    int page,
  ) async {
    requests++;
    return const Success(DiscoveryPage([], metadata: null, hasMore: false));
  }
}

const _refreshError = Error('网络暂不可用');

class _Rank extends RankRepository {
  int requests = 0;
  @override
  Future<LoadingState<DiscoveryPage<Object, void>>> fetch(
    Account account, {
    int? rid,
    int? seasonType,
  }) async => ++requests == 2
      ? _refreshError
      : const Success(DiscoveryPage([], metadata: null, hasMore: false));
}

class _Weekly extends CuratedRepository {
  int requests = 0;
  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, WeeklyCatalog>>> weekly(
    Account account,
    int? number, {
    required bool Function() isCurrent,
  }) async => ++requests == 2
      ? _refreshError
      : Success(
          DiscoveryPage(
            [],
            metadata: WeeklyCatalog(
              series: [],
              config: PopularSeriesConfig(name: '第 42 期', label: '测试期数'),
            ),
            hasMore: false,
          ),
        );
}

class _Pgc extends PgcRepository {
  int timelineRequests = 0;
  int catalogRequests = 0;

  @override
  Future<LoadingState<DiscoveryPage<PgcIndexItem, void>>> catalog(
    Account account,
    int page,
    bool cinema,
  ) async {
    catalogRequests++;
    return const Success(DiscoveryPage([], metadata: null, hasMore: false));
  }

  @override
  Future<LoadingState<DiscoveryPage<TimelineResult, String?>>> timeline(
    Account account,
  ) async => ++timelineRequests == 2
      ? _refreshError
      : Success(
          DiscoveryPage(
            [TimelineResult(date: '11-18', isToday: 1)],
            metadata: null,
            hasMore: false,
          ),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GStorage.setting = await Hive.openBox<dynamic>(
      'discovery-pages',
      bytes: Uint8List(0),
    );
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
  });
  setUp(() async {
    await GStorage.setting.putAll({
      SettingBoxKey.filterBlockedAuthors: false,
      SettingBoxKey.showHotRcmd: false,
      SettingBoxKey.enableSearchWord: false,
      SettingBoxKey.hideTopBar: false,
    });
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    Accounts.accountMode[AccountType.recommend.index] = AnonymousAccount();
    Get.testMode = true;
  });
  tearDown(() {
    Get
      ..deleteAll(force: true)
      ..reset();
  });
  tearDownAll(() => GStorage.setting.close());
  test('热门入口偏好通过 Hive 观察更新，最后订阅释放后销毁', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(hotEntrancesProvider, (_, _) {});
    expect(container.read(hotEntrancesProvider), isFalse);
    await GStorage.setting.put(SettingBoxKey.showHotRcmd, true);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(hotEntrancesProvider), isTrue);
    subscription.close();
    await container.pump();
    expect(container.exists(hotEntrancesProvider), isFalse);
    await GStorage.setting.put(SettingBoxKey.showHotRcmd, false);
    await Future<void>.delayed(Duration.zero);
    expect(container.exists(hotEntrancesProvider), isFalse);
  });
  testWidgets('热门 Widget 注册首页窄句柄，刷新走 Riverpod，卸载释放注册与滚动', (tester) async {
    final repository = _Hot();
    final container = ProviderContainer(
      overrides: [hotRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    DiscoveryPageHandle? registered;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: GetMaterialApp(
          home: Scaffold(
            body: HotPage(
              register: (handle) {
                registered = handle;
                return () => registered = null;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final handle = registered!;
    final scroll = handle.scrollController;
    expect(repository.requests, 1);
    await handle.onRefresh();
    await tester.pump();
    expect(repository.requests, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(registered, isNull);
    expect(scroll.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立热门页的排行榜入口打开榜单', (tester) async {
    await GStorage.setting.put(SettingBoxKey.showHotRcmd, true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hotRepositoryProvider.overrideWithValue(_Hot()),
          rankRepositoryProvider.overrideWithValue(_Rank()),
        ],
        child: const ImageLoadingScope(
          enabled: false,
          child: GetMaterialApp(home: Scaffold(body: HotPage())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(find.byType(RankPage), findsOneWidget);
  });

  testWidgets('独立首页切换排行不夺取主首页的刷新目标', (tester) async {
    await GStorage.setting.putAll({
      SettingBoxKey.tabBarSort: [HomeTabType.hot.index, HomeTabType.rank.index],
      SettingBoxKey.showHotRcmd: true,
    });
    addTearDown(() => GStorage.setting.delete(SettingBoxKey.tabBarSort));
    final hot = _Hot();
    HomePageActions? primary;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hotRepositoryProvider.overrideWithValue(hot),
          rankRepositoryProvider.overrideWithValue(_Rank()),
        ],
        child: ImageLoadingScope(
          enabled: false,
          child: GetMaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  TextButton(
                    onPressed: () => Get.to(const Scaffold(body: HomePage())),
                    child: const Text('预览'),
                  ),
                ],
              ),
              body: HomePage(
                register: (actions) {
                  primary = actions;
                  return () => primary = null;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行榜').last);
    await tester.pumpAndSettle();
    expect(find.byType(RankPage), findsOneWidget);
    final hotRequests = hot.requests;
    await primary!.refresh();
    await tester.pumpAndSettle();
    expect(hot.requests, hotRequests + 1);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.byType(HotPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(primary, isNull);
  });

  for (final page in ['排行榜', '每周必看', '追番时间表']) {
    testWidgets('$page 刷新失败保留快照并提供就地重试', (tester) async {
      final rank = _Rank();
      final weekly = _Weekly();
      final pgc = _Pgc();
      await GStorage.setting.put(SettingBoxKey.showPgcTimeline, true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rankRepositoryProvider.overrideWithValue(rank),
            curatedRepositoryProvider.overrideWithValue(weekly),
            pgcRepositoryProvider.overrideWithValue(pgc),
          ],
          child: GetMaterialApp(
            home: switch (page) {
              '排行榜' => const Scaffold(body: ZonePage(rid: 1)),
              '每周必看' => const PopularSeriesPage(),
              _ => const Scaffold(body: PgcPage(tabType: HomeTabType.bangumi)),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final snapshot = find.text(switch (page) {
        '排行榜' => '没有数据',
        '每周必看' => '第 42 期',
        _ => '11-18 今天',
      });
      final retry = find.text('网络暂不可用 · 重试');
      expect(snapshot, findsOneWidget);
      expect(retry, findsNothing);
      await tester
          .widget<refresh.RefreshIndicator>(
            find.byType(refresh.RefreshIndicator),
          )
          .onRefresh();
      await tester.pumpAndSettle();
      expect(snapshot, findsOneWidget);
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(retry, findsNothing);
      expect(snapshot, findsOneWidget);
      switch (page) {
        case '排行榜':
          expect(rank.requests, 3);
        case '每周必看':
          expect(weekly.requests, 3);
        default:
          expect(pgc.timelineRequests, 3);
          expect(pgc.catalogRequests, 2);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
