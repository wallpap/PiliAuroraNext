import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/account/application/account_roles.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryBox<LoginAccount> accounts;
  late LoginAccount mainAccount;
  late LoginAccount recommendAccount;
  late ProviderContainer container;
  late MessagingSession mainSession;
  final mainUpdates = <Account>[];
  final recommendUpdates = <Account>[];

  LoginAccount login(int mid, {String csrf = 'fixture'}) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;

  void expectMainUnchanged() {
    expect(mainUpdates, [same(mainAccount)]);
    expect(container.read(mainAccountProvider), same(mainAccount));
    expect(Messaging.instance.session, same(mainSession));
    expect(mainSession.isActive, isTrue);
  }

  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    accounts = MemoryBox<LoginAccount>();
    Accounts.account = accounts;
    AnonymousAccount().activated = true;
  });

  setUp(() {
    accounts.data.clear();
    for (final role in AccountType.values) {
      Accounts.accountMode[role.index] = AnonymousAccount();
    }
    mainAccount = login(100)..type.add(AccountType.main);
    recommendAccount = login(200)..type.add(AccountType.recommend);
    Accounts.accountMode[AccountType.main.index] = mainAccount;
    Accounts.accountMode[AccountType.recommend.index] = recommendAccount;
    accounts.data.addAll({'100': mainAccount, '200': recommendAccount});
    mainSession = Messaging.instance.session;
    mainUpdates.clear();
    recommendUpdates.clear();
    container = ProviderContainer()
      ..listen(
        mainAccountProvider,
        (_, next) => mainUpdates.add(next),
        fireImmediately: true,
      )
      ..listen(
        recommendAccountProvider,
        (_, next) => recommendUpdates.add(next),
        fireImmediately: true,
      );
  });

  tearDown(() {
    container.dispose();
    for (final role in AccountType.values) {
      Accounts.accountMode[role.index] = AnonymousAccount();
    }
    Messaging.instance.session;
  });

  test('应用卸载关闭消息订阅并拒绝迟到请求，新会话可独立建立', () async {
    final oldOwner = Messaging.instance;
    final oldSession = oldOwner.session;
    final response = Completer<LoadingState<int>>();
    final request = oldSession.run((_) => response.future);
    final closed = oldSession.changes.drain<void>();

    Messaging.closeApplicationSession();
    response.complete(const Success(42));

    await closed;
    expect(await request, isA<Error>());
    expect(oldOwner.session.isActive, isFalse);
    final newSession = Messaging.instance.session;
    expect(newSession.isActive, isTrue);
    expect(newSession.key, isNot(oldSession.key));
  });

  test('主账号恢复原凭据后不接收上一会话结果，视频角色独立', () {
    Accounts.accountMode[AccountType.video.index] = recommendAccount;
    final mainRequest = AccountScope.capture();
    final videoRequest = AccountScope.captureVideo();

    Accounts.replaceCredentials(login(100, csrf: 'renewed'));
    Accounts.replaceCredentials(mainAccount);

    expect(mainRequest.isCurrent, isFalse);
    expect(AccountScope.capture().isCurrent, isTrue);
    expect(videoRequest.isCurrent, isTrue);
  });

  test('真实推荐账号切换发布同 mid 的新凭据，不重建主账号及消息 Session', () async {
    final next = login(200, csrf: 'renewed');
    await Accounts.set(AccountType.recommend, next);
    await container.pump();

    expect(recommendUpdates, [same(recommendAccount), same(next)]);
    expect(container.read(recommendAccountProvider), same(next));
    expect(next.type, contains(AccountType.recommend));
    expectMainUnchanged();
  });

  test('仅注销推荐账号立即发布匿名身份，保持主账号及消息 Session', () async {
    await Accounts.deleteAll({recommendAccount});
    await container.pump();

    expect(recommendUpdates, [
      same(recommendAccount),
      same(AnonymousAccount()),
    ]);
    expect(container.read(recommendAccountProvider).isLogin, isFalse);
    expectMainUnchanged();
  });

  test('提交旧角色草稿时使用同 UID 最新保存的凭据', () async {
    const roles = AccountRoles();
    final draft = roles.selection();
    final choices = List.of(draft.roles)..[AccountType.video.index] = 200;
    final renewed = login(200, csrf: 'renewed');
    Accounts.replaceCredentials(renewed);
    await accounts.put('200', renewed);

    expect(await roles.apply(draft, choices), isTrue);
    expect(Accounts.video, same(renewed));
    expect(accounts.get('200'), same(renewed));
    expectMainUnchanged();
  });

  test('仅重新登录推荐账号使旧凭据失效，保持主账号及消息 Session', () async {
    final next = login(200, csrf: 'renewed');
    Accounts.replaceCredentials(next);
    await container.pump();

    expect(recommendUpdates, [same(recommendAccount), same(next)]);
    expect(container.read(recommendAccountProvider), same(next));
    expectMainUnchanged();
  });

  test('仅主账号凭据变化不重建推荐账号，消息 Session 继续随主账号替换', () async {
    final next = login(100, csrf: 'renewed');
    Accounts.replaceCredentials(next);
    await container.pump();

    expect(mainUpdates, [same(mainAccount), same(next)]);
    expect(recommendUpdates, [same(recommendAccount)]);
    expect(mainSession.isActive, isFalse);
    expect(Messaging.instance.session.account, same(next));
    expect(container.read(recommendAccountProvider), same(recommendAccount));
  });

  test('共享账号重新登录同时替换两个角色，只替换一次消息 Session', () async {
    await Accounts.set(AccountType.recommend, mainAccount);
    await container.pump();
    expectMainUnchanged();
    var messagingChanges = 0;
    void changed() => messagingChanges++;
    Messaging.instance.current.addListener(changed);
    addTearDown(() => Messaging.instance.current.removeListener(changed));

    final next = login(100, csrf: 'renewed');
    Accounts.replaceCredentials(next);
    await container.pump();

    expect(mainUpdates, [same(mainAccount), same(next)]);
    expect(recommendUpdates, [
      same(recommendAccount),
      same(mainAccount),
      same(next),
    ]);
    expect(next.type, containsAll([AccountType.main, AccountType.recommend]));
    expect(messagingChanges, 1);
  });

  test('账号刷新发布存储中的推荐凭据', () async {
    final next = login(200, csrf: 'renewed')..type.add(AccountType.recommend);
    await accounts.put('200', next);
    await Accounts.refresh();
    await container.pump();

    expect(mainUpdates, [same(mainAccount)]);
    expect(recommendUpdates, [same(recommendAccount), same(next)]);
    expect(container.read(recommendAccountProvider), same(next));
  });

  test('清空账号同时发布主账号及推荐账号的匿名身份', () async {
    await Accounts.clear();
    await container.pump();

    expect(mainUpdates, [same(mainAccount), same(AnonymousAccount())]);
    expect(recommendUpdates, [
      same(recommendAccount),
      same(AnonymousAccount()),
    ]);
    expect(mainSession.isActive, isFalse);
    expect(Messaging.instance.session.account.isLogin, isFalse);
  });

  test('最后一个订阅释放后不继续接收账号变更', () {
    container.dispose();
    Accounts.replaceCredentials(login(200, csrf: 'renewed'));

    expect(mainUpdates, [same(mainAccount)]);
    expect(recommendUpdates, [same(recommendAccount)]);
    container = ProviderContainer();
    expect(
      container.read(recommendAccountProvider),
      same(Accounts.get(AccountType.recommend)),
    );
  });
}
