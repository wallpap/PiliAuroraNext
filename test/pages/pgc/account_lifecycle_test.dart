import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/pgc_feed.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

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
  Future<void> flush() async {
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  LoginAccount account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'synthetic'}),
    null,
    null,
  );

  test('PGC follows do not retain an old account response', () async {
    Accounts.accountMode[AccountType.main.index] = account(123);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = pgcFollowsProvider((owner: Object(), cinema: false));
    container.listen(provider, (_, _) {});
    await flush();
    expect(adapter.pending, hasLength(1));
    Accounts.replaceCredentials(account(123));
    await flush();
    adapter.json(0, {
      'code': 0,
      'data': {
        'total': 1,
        'list': [
          {'season_id': 123, 'title': 'account-A-only'},
        ],
      },
    });
    await flush();
    expect(adapter.pending, hasLength(2));
    expect(container.read(provider).loadingMore, isTrue);
    adapter.json(1, {
      'code': 0,
      'data': {
        'total': 1,
        'list': [
          {'season_id': 456, 'title': 'account-B'},
        ],
      },
    });
    await flush();
    expect(container.read(provider).loadingMore, isFalse);
    expect(container.read(provider).loading.dataOrNull?.single.seasonId, 456);
    // 旧请求不能成为账号 B 的当前订阅快照。
    expect(
      container
              .read(provider)
              .loading
              .dataOrNull
              ?.any((e) => e.seasonId == 123) ??
          false,
      isFalse,
    );
  });
}
