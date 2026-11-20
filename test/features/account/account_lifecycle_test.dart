import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/account/application/account_preferences.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/presentation/account_dashboard.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/data/favorite_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/models/common/theme/theme_type.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/application/coin_balance.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';
import 'profile_fixture.dart';

class DashboardFolders extends FavoriteRepository {
  final owners = <Account>[];
  @override
  Future<FeedPage<Object, FavoriteMetadata>> page(
    Account account,
    FavoriteQuery query,
    Object? cursor, {
    bool Function()? isCurrent,
  }) async {
    owners.add(account);
    return FeedPage([], metadata: FavoriteMetadata(total: account.mid));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryBox<LoginAccount> accounts;
  late FakeProfiles repository;
  late AccountProfile module;
  late FavoriteLibrary favorites;
  late DashboardFolders folders;
  late ProviderContainer container;
  late LoginAccount main;
  late LoginAccount heartbeat;

  setUpAll(() async {
    GStorage.setting = await Hive.openBox<dynamic>(
      'account-preferences-test',
      bytes: Uint8List(0),
    );
    GStorage.localCache = MemoryBox<dynamic>();
    GStorage.video = MemoryBox<dynamic>();
    GStorage.userInfo = MemoryBox<UserInfoData>();
    GStorage.reply = null;
    Accounts.account = accounts = MemoryBox<LoginAccount>();
    AnonymousAccount().activated = true;
  });
  setUp(() async {
    await GStorage.setting.clear();
    accounts.data.clear();
    for (final role in AccountType.values) {
      Accounts.accountMode[role.index] = AnonymousAccount();
    }
    main = login(1)..type.add(AccountType.main);
    heartbeat = login(2)..type.add(AccountType.heartbeat);
    accounts.data.addAll({'1': main, '2': heartbeat});
    await Accounts.refresh();
    repository = FakeProfiles();
    module = AccountProfile(repository);
    folders = DashboardFolders();
    favorites = FavoriteLibrary(folders);
    container = ProviderContainer(
      overrides: [
        accountProfileModuleProvider.overrideWithValue(module),
        favoriteLibraryProvider.overrideWithValue(favorites),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    for (final pending in [
      ...repository.requests,
      ...repository.statRequests,
    ]) {
      if (!pending.isCompleted) pending.complete(const Error('测试结束'));
    }
    await module.dispose();
    await favorites.close();
  });
  tearDownAll(Hive.close);

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  Future<void> switchMain(LoginAccount next) async {
    for (final stored in accounts.values) {
      stored.type.remove(AccountType.main);
    }
    next.type.add(AccountType.main);
    accounts.data['${next.mid}'] = next;
    await Accounts.refresh();
    await settle();
  }

  test('真实角色通知重建资料与统计，拒绝旧账号和同 UID 旧凭据的响应', () async {
    repository.holdStats = true;
    container
      ..listen(accountProfileProvider, (_, _) {})
      ..listen(accountStatsProvider, (_, _) {});
    await settle();
    final first = container.read(accountStatsProvider.future);
    await switchMain(login(3));
    expect(container.read(accountProfileProvider).info, isNull);
    expect(container.read(accountStatsProvider).isLoading, isTrue);
    repository.requests[0].complete(Success(info(1, 'old')));
    repository.statRequests[0].complete(const Success(UserStat(follower: 99)));
    repository.requests[1].complete(Success(info(3, 'third')));
    repository.statRequests[1].complete(const Success(UserStat(follower: 3)));
    await first;
    await settle();
    expect(container.read(accountProfileProvider).info?.uname, 'third');
    expect(container.read(accountStatsProvider).value?.follower, 3);
    final pending = container.read(accountProfileProvider.notifier).refresh();
    final renewed = login(3, csrf: 'renewed');
    Accounts.replaceCredentials(renewed);
    await settle();
    repository.requests[2].complete(Success(info(3, 'old credentials')));
    await pending;
    repository.requests[3].complete(Success(info(3, 'renewed')));
    repository.statRequests[2].complete(const Success(UserStat(follower: 4)));
    await settle();
    expect(
      repository.owners.map((owner) => (owner.mid, owner.csrf)),
      [(1, 'fixture'), (3, 'fixture'), (3, 'fixture'), (3, 'renewed')],
    );
    expect(repository.statOwners.map((owner) => (owner.mid, owner.csrf)), [
      (1, 'fixture'),
      (3, 'fixture'),
      (3, 'renewed'),
    ]);
    expect(container.read(accountProfileProvider).info?.uname, 'renewed');
    expect(repository.saved.map((info) => info.uname), ['third', 'renewed']);
  });

  test('临时无痕通知历史账号，永久保存与退出维护真实角色及持久化标记', () async {
    container
      ..listen(incognitoProvider, (_, _) {})
      ..listen(historyAccountProvider, (_, _) {});
    expect(container.read(incognitoProvider), isFalse);
    expect(container.read(historyAccountProvider), same(heartbeat));
    AccountPrivacy.enableTemporarily();
    expect(container.read(incognitoProvider), isTrue);
    expect(container.read(historyAccountProvider), same(main));
    expect(heartbeat.type, contains(AccountType.heartbeat));
    await AccountPrivacy.saveEnabled();
    expect(heartbeat.type, isNot(contains(AccountType.heartbeat)));
    expect(container.read(incognitoProvider), isTrue);
    await AccountPrivacy.disable();
    expect(container.read(incognitoProvider), isFalse);
    expect(Accounts.heartbeat, same(main));
    expect(main.type, containsAll([AccountType.main, AccountType.heartbeat]));
  });

  test('临时无痕期间更换凭据，后续保存不会把旧凭据写回账号存储', () async {
    AccountPrivacy.enableTemporarily();
    final renewed = login(2, csrf: 'renewed');
    Accounts.replaceCredentials(renewed);
    await AccountPrivacy.saveEnabled();
    final stored = accounts.get('2')!;
    expect(stored.mid, 2);
    expect(stored.csrf, 'renewed');
    expect(stored.type, isNot(contains(AccountType.heartbeat)));
  });

  test('主题直接订阅偏好，其他设置入口写入也会更新个人中心', () async {
    container.listen(accountThemeProvider, (_, _) {});
    expect(container.read(accountThemeProvider), ThemeType.system);
    await GStorage.setting.put(SettingBoxKey.themeMode, ThemeType.dark.index);
    await settle();
    expect(container.read(accountThemeProvider), ThemeType.dark);
    expect(
      await container.read(accountThemeProvider.notifier).next(),
      ThemeType.system,
    );
    await settle();
    expect(container.read(accountThemeProvider), ThemeType.system);
  });

  test('缓存写入跨账号串行，旧同 UID 写入先完成后仍由新确认资料收尾', () async {
    final writing = Completer<void>();
    repository.beforeSave = (_, info) =>
        info.uname == 'before' ? writing.future : Future.value();
    final before = module.updateDisplay(main, name: 'before');
    final renewed = login(1);
    Accounts.replaceCredentials(renewed);
    final after = module.updateDisplay(renewed, name: 'after');
    expect(module.cached(renewed)?.uname, 'after');
    writing.complete();
    await Future.wait([before, after]);
    expect(repository.saved.last.uname, 'after');
    expect(repository.cache?.uname, 'after');
  });

  testWidgets('个人中心展示确认资料并实时接收编辑，切号后隐藏旧昵称与统计', (tester) async {
    await tester.runAsync(() async {
      container.listen(accountProfileProvider, (_, _) {});
      await settle();
      repository.requests.single.complete(
        Success(info(1, 'first')..face = null),
      );
      await settle();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AccountDashboard(
              showBackBtn: false,
              showReply: false,
              wrapScroll: (child) => child,
              onSwitchAccount: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    expect(folders.owners, [same(main)]);
    await tester.runAsync(() => module.updateDisplay(main, name: 'edited'));
    await tester.pump();
    expect(find.text('edited'), findsOneWidget);
    repository.holdStats = true;
    await tester.runAsync(() => switchMain(login(3)));
    await tester.pump();
    expect(find.text('edited'), findsNothing);
    expect(find.text('7'), findsNothing);
    await tester.runAsync(() async {
      repository.requests.last.complete(Success(info(3, 'third')..face = null));
      repository.statRequests.last.complete(
        const Success(UserStat(follower: 3)),
      );
      await settle();
    });
    await tester.pump();
    expect(find.text('third'), findsOneWidget);
    expect(folders.owners.last.mid, 3);
    expect(CoinBalance.instance.amount, 12);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
}
