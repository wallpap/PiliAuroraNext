import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/login_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../support/controlled_http_adapter.dart';
import '../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final adapter = ControlledHttpAdapter();
  final dispatched = adapter.waitForRequests;
  final profile = MemoryBox<UserInfoData>();
  late Account previousAccount;
  late Account first;
  final mainIndex = AccountType.main.index;

  Map<String, Object?> info({int money = 10}) => {
    'code': 0,
    'data': {
      'isLogin': true,
      'face': 'fixture-face',
      'money': money,
      'mid': 123,
    },
  };
  Account account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture'}),
    null,
    null,
  );

  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    GStorage.userInfo = profile;
    Request();
    Request.dio.interceptors.clear();
    Request.dio.httpClientAdapter = adapter;
    Get.testMode = true;
  });
  setUp(() {
    previousAccount = Accounts.main;
    first = account(123);
    Accounts.accountMode[mainIndex] = first;
    profile.data.clear();
    adapter.requests.clear();
    adapter.pending.clear();
    GlobalData().coins = 30;
  });
  tearDown(() {
    Accounts.accountMode[mainIndex] = previousAccount;
    Get.reset();
  });
  tearDownAll(() => Request.dio.close(force: true));

  test('硬币请求绑定发起账号，切号后迟到结果不写入共享余额', () async {
    final pending = Request.setCoin();
    await dispatched(1);
    expect(adapter.requests.single.extra['account'], same(first));
    Accounts.accountMode[mainIndex] = account(456);
    adapter.json(0, {
      'code': 0,
      'data': {'money': 99},
    });
    await pending;
    expect(GlobalData().coins, 30);
    final current = Request.setCoin();
    await dispatched(2);
    adapter.json(1, {
      'code': 0,
      'data': {'money': 12},
    });
    await current;
    expect(GlobalData().coins, 12);
  });

  test('登录查询在切号后不再同步旧头像、Cookie、缓存或余额', () async {
    final pending = LoginUtils.onLoginMain();
    await dispatched(1);
    expect(adapter.requests.single.extra['account'], same(first));
    Accounts.accountMode[mainIndex] = account(456);
    adapter.json(0, info());
    await pending;
    expect(profile.data, isEmpty);
    expect(GlobalData().coins, 30);
  });

  test('真实 HTTP 资料查询忽略切号或释放后的结果', () async {
    for (final close in [false, true]) {
      adapter.requests.clear();
      adapter.pending.clear();
      var active = true;
      final pending = AccountProfile.legacy.refresh(
        first,
        isActive: () => active,
      );
      await dispatched(1);
      if (close) {
        active = false;
      } else {
        Accounts.accountMode[mainIndex] = account(456);
      }
      adapter.json(0, info());
      expect(await pending, isNull);
      expect(profile.data, isEmpty);
      expect(GlobalData().coins, 30);
      expect(adapter.requests, hasLength(1));
      Accounts.accountMode[mainIndex] = first;
    }
  });

  test('同账号最新查询优先，旧未登录响应不能触发登出', () async {
    final old = AccountProfile.legacy.refresh(first);
    final latest = AccountProfile.legacy.refresh(first);
    await dispatched(2);
    adapter.json(1, info(money: 12));
    expect((await latest)?.result.data.money, 12);
    adapter.json(0, {'code': -101, 'message': '账号未登录'});
    expect(await old, isNull);
    expect(Accounts.main, same(first));
    expect(profile.data['userInfoCache:123']!.mid, 123);
    expect(GlobalData().coins, 12);
  });
}
