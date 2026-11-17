import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/data/hot_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/pages/home/controller.dart';
import 'package:pili_aurora_next/pages/hot/view.dart';
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
    final home = Get.put(HomeController());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GetMaterialApp(home: Scaffold(body: HotPage())),
      ),
    );
    await tester.pump();
    await tester.pump();
    final handle = home.registeredPage(HomeTabType.hot)!;
    final scroll = handle.scrollController;
    expect(repository.requests, 1);
    await handle.onRefresh();
    await tester.pump();
    expect(repository.requests, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(home.registeredPage(HomeTabType.hot), isNull);
    expect(scroll.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });
}
