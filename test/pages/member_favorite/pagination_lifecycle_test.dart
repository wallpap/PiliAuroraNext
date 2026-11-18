import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/application/space_favorites.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/member_favorites.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_http_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledHttpAdapter adapter;
  late List<Account> originals;
  setUpAll(() async {
    GStorage.setting = await Hive.openBox(
      'final-audit-settings',
      bytes: Uint8List(0),
    );
    GStorage.video = await Hive.openBox(
      'final-audit-video',
      bytes: Uint8List(0),
    );
    GStorage.localCache = await Hive.openBox(
      'final-audit-cache',
      bytes: Uint8List(0),
    );
    GStorage.userInfo = await Hive.openBox<UserInfoData>(
      'final-audit-user',
      bytes: Uint8List(0),
    );
    originals = List.of(Accounts.accountMode);
    Request();
    Request.dio.interceptors.clear();
    Get.testMode = true;
  });
  setUp(() {
    adapter = ControlledHttpAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    adapter.close();
    Accounts.accountMode.setAll(0, originals);
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await Hive.close();
  });

  final provider = spaceFavoritesProvider((owner: Object(), mid: 123));
  Map<String, dynamic> section(int id, [int count = 5]) => {
    'mediaListResponse': {
      'count': count,
      'list': [
        {'id': id},
      ],
    },
  };
  Map<String, dynamic> page(List<int> ids, bool more) => {
    'code': 0,
    'data': {
      'has_more': more,
      'list': [
        for (final id in ids) {'id': id},
      ],
    },
  };
  Map<String, dynamic> first(int a, int b) => {
    'code': 0,
    'data': [section(a), section(b)],
  };
  Future<void> flush() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<SpaceFavorites> start(
    ProviderContainer container, [
    Map<String, dynamic>? payload,
  ]) async {
    if (!container.exists(provider)) container.listen(provider, (_, _) {});
    await adapter.waitForRequests(1);
    adapter.json(0, payload ?? first(11, 12));
    await flush();
    return container.read(provider.notifier);
  }

  FavoriteSection read(ProviderContainer container, bool subscribed) {
    final sections = container.read(provider).data;
    return (subscribed ? sections.subscriptions : sections.folders)!;
  }

  for (final subscribed in [false, true]) {
    test('同一分区同页只请求一次，续页失败不推进并可重试 ($subscribed)', () async {
      final container = ProviderContainer.test();
      final folders = await start(container);
      final pending = folders.more(subscribed: subscribed);
      expect(await folders.more(subscribed: subscribed), isNull);
      await adapter.waitForRequests(2);
      adapter.json(1, {
        'code': 0,
        'data': {'has_more': true},
      });
      expect(await pending, isA<Error>());
      expect(read(container, subscribed).nextPage, 2);
      final retry = folders.more(subscribed: subscribed);
      await adapter.waitForRequests(3);
      adapter.json(2, page([22, 22], true));
      expect(await retry, isA<Success>());
      expect(read(container, subscribed).items.map((item) => item.id), [
        subscribed ? 12 : 11,
        22,
      ]);
      expect(read(container, subscribed).nextPage, 3);
    });

    test('无内容终页可空，缺分页证据不能当成功 ($subscribed)', () async {
      Future<LoadingState<MemberFavoritePage>> load() =>
          MemberFavoritesHttp.folders(
            account: Accounts.main,
            mid: 123,
            page: 2,
            subscribed: subscribed,
          );
      var pending = load();
      await adapter.waitForRequests(1);
      adapter.json(0, {
        'code': 0,
        'data': {'has_more': false, 'list': null},
      });
      expect((await pending).data.items, isEmpty);
      pending = load();
      await adapter.waitForRequests(2);
      adapter.json(1, {
        'code': 0,
        'data': {'list': []},
      });
      expect(await pending, isA<Error>());
    });
  }

  test('刷新使在途续页和旧删除回调失效，两个分区可独立加载', () async {
    final container = ProviderContainer.test();
    final folders = await start(container);
    final deleted = folders.deletionAction(
      false,
      read(container, false).items.single,
    );
    final old = folders.more(subscribed: false);
    final other = folders.more(subscribed: true);
    await adapter.waitForRequests(3);
    final refresh = folders.refresh();
    expect(await folders.more(subscribed: false), isNull);
    await adapter.waitForRequests(4);
    adapter.json(3, first(33, 44));
    await refresh;
    adapter
      ..json(2, page([77], false))
      ..json(1, page([22], false));
    await Future.wait([old, other]);
    deleted(true);
    expect(adapter.requests, hasLength(4));
    expect(read(container, false).items.single.id, 33);
    expect(read(container, true).items.single.id, 44);
    expect(read(container, false).nextPage, 2);
    final next = folders.more(subscribed: false);
    await adapter.waitForRequests(5);
    adapter.json(4, page([55], false));
    await next;
    expect(read(container, false).items.map((e) => e.id), [33, 55]);
    expect(read(container, false).nextPage, isNull);
  });

  test('当前收藏夹删除后回读首屏，不沿旧偏移翻页', () async {
    final container = ProviderContainer.test();
    final folders = await start(container);
    folders.deletionAction(false, read(container, false).items.single)(true);
    expect(read(container, false).items, isEmpty);
    expect(await folders.more(subscribed: false), isNull);
    await adapter.waitForRequests(2);
    adapter.json(1, first(33, 44));
    await flush();
    expect(read(container, false).items.single.id, 33);
  });

  test('不完整首屏不给旧分区开放分页', () async {
    final container = ProviderContainer.test();
    final folders = await start(container, {
      'code': 0,
      'data': [section(11)],
    });
    expect(container.read(provider), isA<Error>());
    expect(await folders.more(subscribed: false), isNull);
    expect(adapter.requests, hasLength(1));
  });

  test('同 UID 换凭据立即隐藏旧分区，旧分页不写回；关闭后停止订阅', () async {
    LoginAccount login(String token) => LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': token}),
      null,
      null,
    );
    final old = login('old');
    Accounts.accountMode[AccountType.main.index] = old;
    final container = ProviderContainer.test();
    final subscription = container.listen(provider, (_, _) {});
    final folders = await start(container);
    final paging = folders.more(subscribed: false);
    await adapter.waitForRequests(2);
    final next = login('new');
    Accounts.replaceCredentials(next);
    await adapter.waitForRequests(3);
    expect(container.read(provider), isA<Loading>());
    expect(adapter.requests[1].extra['account'], same(old));
    expect(adapter.requests[2].extra['account'], same(next));
    adapter
      ..json(2, first(33, 44))
      ..json(1, page([99], true));
    await paging;
    await flush();
    expect(read(container, false).items.single.id, 33);
    subscription.close();
    await container.pump();
    Accounts.replaceCredentials(login('closed'));
    await flush();
    expect(adapter.requests, hasLength(3));
  });
}
