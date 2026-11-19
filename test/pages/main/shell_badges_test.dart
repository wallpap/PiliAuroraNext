import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/app_shell/application/shell_badges.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/models/common/msg/msg_unread_type.dart';
import 'package:pili_aurora_next/models/common/nav_bar_config.dart';
import 'package:pili_aurora_next/services/messaging/overview.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/settings/badge_preferences.dart';
import 'package:pili_aurora_next/services/settings/navigation_preferences.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = _PendingBadgeSettings();
  setUpAll(() {
    GStorage.setting = store;
    GStorage.localCache = MemoryBox<dynamic>();
  });
  setUp(() async {
    store.pendingMode = null;
    await store.clear();
  });

  test('导航与首页保留有效标签，并回退到可用首页', () async {
    await store.putAll({
      SettingBoxKey.navBarSort: [91, NavigationBarType.mine.index, 'old', 2],
      SettingBoxKey.defaultHomePage: -1,
      SettingBoxKey.tabBarSort: [
        99,
        HomeTabType.hot.index,
        'old',
        HomeTabType.rcmd.index,
        HomeTabType.hot.index,
      ],
    });
    final main = NavigationPreferences.read();
    expect(main.tabs, [NavigationBarType.mine]);
    expect(main.index, 0);
    final (:tabs, :index) = NavigationPreferences.readHome();
    expect(tabs, [HomeTabType.hot, HomeTabType.rcmd]);
    expect(tabs[index], HomeTabType.rcmd);

    await store.put(SettingBoxKey.navBarSort, [91]);
    final fallback = NavigationPreferences.read();
    expect(fallback.tabs, NavigationBarType.values);
    expect(fallback.tabs[fallback.index], NavigationBarType.home);
  });

  test('消息角标只响应已保存设置，启动、隐藏和恢复不会重复查询', () async {
    final previous = Accounts.main;
    final account = Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'fixture'}),
      null,
      null,
    );
    addTearDown(() => Accounts.accountMode[AccountType.main.index] = previous);
    final session = Messaging.instance.session;
    expect(session.account, same(account));
    var queries = 0;
    final overview = UnreadOverview(
      session,
      query: () async {
        queries++;
        return const UnreadQueryResult({});
      },
    );
    addTearDown(overview.dispose);
    final container = ProviderContainer(
      overrides: [
        overviewHandleProvider.overrideWithValue(overview),
      ],
    );
    addTearDown(container.dispose);
    final preferences = container.read(badgePreferencesProvider);
    final subscription = container.listen(shellBadgesProvider, (_, _) {});
    final badges = subscription.read();
    final detach = badges.attach(hasHome: true, hasDynamics: false);
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    await flush();
    expect(queries, 0);
    badges
      ..start(onDynamics: false)
      ..checkMessages();
    await flush();
    expect(queries, 1);

    final pending = store.pendingMode = Completer<void>();
    final hide = preferences.saveMessageMode(DynamicBadgeMode.hidden);
    await flush();
    expect(badges.message.value.mode, DynamicBadgeMode.number);
    pending.complete();
    await hide;
    await preferences.saveMessageTypes({MsgUnReadType.reply});
    await flush();
    expect(badges.message.value.mode, DynamicBadgeMode.hidden);
    expect(badges.message.value.types, {MsgUnReadType.reply});
    expect(queries, 1);

    await preferences.saveMessageMode(DynamicBadgeMode.point);
    await flush();
    expect(badges.message.value.mode, DynamicBadgeMode.point);
    expect(queries, 2);
    detach();
    final savingAfterDetach = store.pendingMode = Completer<void>();
    final save = preferences.saveMessageMode(DynamicBadgeMode.number);
    final changes = preferences.changes.listen(
      (_) => fail('释放时仍有未完成写入，不应继续发出角标事件'),
    );
    addTearDown(changes.cancel);
    final completed = changes.asFuture<void>();
    await flush();
    expect(queries, 2);
    subscription.close();
    await container.pump();
    expect(container.exists(shellBadgesProvider), isFalse);
    container.dispose();
    savingAfterDetach.complete();
    await save;
    await completed;
    expect(preferences.messageMode, DynamicBadgeMode.number);
    expect(queries, 2);
  });
}

class _PendingBadgeSettings extends MemoryBox<dynamic> {
  Completer<void>? pendingMode;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (key == SettingBoxKey.msgBadgeMode) await pendingMode?.future;
    await super.put(key, value);
  }
}
