import 'package:pili_aurora_next/features/account/domain/account_type.dart';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/generated/bilibili/app/dynamic/v1.pb.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/features/app_shell/application/shell_badges.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/controlled_http_adapter.dart';

class _Adapter extends ControlledHttpAdapter {
  void red(int i, int count) => pending[i].complete(
    ResponseBody.fromBytes(
      GrpcReq.compressProtobuf(
        DynRedReply(dynRedItem: DynRedItem(count: Int64(count)))
            .writeToBuffer(),
      ),
      200,
      headers: {
        'grpc-status': ['0'],
        'content-type': ['application/grpc'],
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
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
  });
  setUp(() {
    adapter = _Adapter();
    Request.dio.httpClientAdapter = adapter;
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'fixture'}),
      null,
      null,
    );
  });
  tearDown(() {
    adapter.close();
    Accounts.accountMode.setAll(0, originals);
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

  ShellBadges startBadges() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(shellBadgesProvider, (_, _) {});
    return subscription.read()
      ..attach(hasHome: false, hasDynamics: true)
      ..start(onDynamics: false);
  }

  test('同 UID 换凭据清空角标并拒绝旧响应', () async {
    final badges = startBadges();
    await flush();
    adapter.red(0, 8);
    await flush();
    expect(badges.dynamicCount.value, 8);
    Accounts.replaceCredentials(
      LoginAccount(
        BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'rotated'}),
        null,
        null,
      ),
    );
    expect(badges.dynamicCount.value, 0);
    await flush();
    Accounts.replaceCredentials(
      LoginAccount(
        BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'new'}),
        null,
        null,
      ),
    );
    await flush();
    expect(adapter.pending, hasLength(3));
    adapter
      ..red(2, 3)
      ..red(1, 7);
    await flush();
    expect(badges.dynamicCount.value, 3);
  });

  test('进入动态后清除的角标不会被在途查询恢复', () async {
    final badges = startBadges();
    await flush();
    expect(adapter.pending, hasLength(1));
    badges.clearDynamics();
    adapter.red(0, 7);
    await flush();
    expect(badges.dynamicCount.value, 0);
  });
}
