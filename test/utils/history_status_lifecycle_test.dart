import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/history/data/history_repository.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

import '../support/controlled_http_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledHttpAdapter adapter;
  late List<Account> previousAccounts;
  setUpAll(() async {
    GStorage.setting = await Hive.openBox(
      'history-status-setting',
      bytes: Uint8List(0),
    );
    GStorage.video = await Hive.openBox(
      'history-status-video',
      bytes: Uint8List(0),
    );
    GStorage.localCache = await Hive.openBox(
      'history-status-cache',
      bytes: Uint8List(0),
    );
    previousAccounts = List<Account>.of(Accounts.accountMode);
    Request();
    Request.dio.interceptors.clear();
  });
  setUp(() {
    adapter = ControlledHttpAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    adapter.close();
    Accounts.accountMode.setAll(0, previousAccounts);
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await Hive.close();
  });

  Account account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'synthetic'}),
    null,
    null,
  );

  test(
    'old account response cannot replace current history pause',
    () async {
      Accounts.accountMode[AccountType.heartbeat.index] = account(123);
      final old = HistoryLibrary.legacy.syncActiveAccountStatus();
      await adapter.waitForRequests(1);
      Accounts.accountMode[AccountType.heartbeat.index] = account(456);
      final latest = HistoryLibrary.legacy.syncActiveAccountStatus();
      await adapter.waitForRequests(2);
      adapter.json(1, {'code': 0, 'data': true});
      await latest;
      expect(Pref.historyPause, isTrue);
      adapter.json(0, {'code': 0, 'data': false});
      await old;
      expect(Pref.historyPause, isTrue);
    },
  );

  test('关闭历史服务后忽略迟到的暂停状态', () async {
    final owner = account(789);
    Accounts.accountMode[AccountType.heartbeat.index] = owner;
    final previous = Pref.historyPause;
    final library = HistoryLibrary(HistoryRepository());
    final updates = library.pauseChanges.toList();
    final pending = library.status(owner);
    await adapter.waitForRequests(1);

    await library.close();
    adapter.json(0, {'code': 0, 'data': !previous});

    expect((await pending).isSuccess, isFalse);
    expect(await updates, isEmpty);
    expect(Pref.historyPause, previous);
  });
}
