import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Intro extends PgcIntroController {
  int target = 1;
  @override
  int get followSeasonId => target;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  final controllers = <GetxController>[];
  LoginAccount account(int id) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': 'fixture-$id'}),
    null,
    null,
  );
  late Account original;
  T own<T extends GetxController>(T controller) {
    controllers.add(controller);
    return controller;
  }

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    GStorage.userInfo = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    original = account(1);
    Accounts.accountMode[AccountType.main.index] = original;
    requests.clear();
  });
  tearDown(() {
    for (final controller in controllers) {
      controller.onDelete();
    }
    controllers.clear();
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    GetMaterialApp(
      builder: FlutterSmartDialog.init(),
      home: const Scaffold(),
    ),
  );
  Future<void> finish(WidgetTester tester) async {
    final dismissed = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissed;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  test('追番状态失败可重试，未关注不要求分组，切号和换目标拒绝迟到结果', () async {
    final controller = own(_Intro());
    var pending = controller.queryIsFollowed();
    await interceptor.waitForRequests(1);
    requests[0].reply.complete({'code': -403, 'message': '拒绝查询'});
    await pending;
    expect(controller.collection.tracking.value.result, isA<Error>());
    pending = controller.queryIsFollowed();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({
      'code': 0,
      'result': {'follow': 0},
    });
    await pending;
    expect(controller.collection.tracking.value.result.data.followed, isFalse);
    expect(controller.collection.tracking.value.result.data.status, isNull);
    pending = controller.queryIsFollowed();
    await interceptor.waitForRequests(3);
    controller.target = 2;
    Accounts.accountMode[AccountType.main.index] = account(2);
    requests[2].reply.complete({
      'code': 0,
      'result': {'follow': 1, 'follow_status': 3},
    });
    await pending;
    expect(controller.collection.tracking.value.result, isA<Loading>());
    expect(requests[2].options.extra['account'], same(original));
  });

  testWidgets('追番写入互斥，确认成功淘汰早先查询，失败保留已确认状态', (tester) async {
    await mount(tester);
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
    final controller = own(_Intro());
    await tester.runAsync(() async {
      final reading = controller.queryIsFollowed();
      await interceptor.waitForRequests(1);
      final writing = controller.pgcAdd();
      await interceptor.waitForRequests(2);
      await controller.pgcAdd();
      expect(requests, hasLength(2));
      expect(controller.collection.tracking.value.busy, isTrue);
      requests[1].reply.complete({'code': 0});
      await writing;
      requests[0].reply.complete({
        'code': 0,
        'result': {'follow': 0},
      });
      await reading;
      expect(controller.collection.tracking.value.result.data.followed, isTrue);
      final deleting = controller.pgcDel();
      await interceptor.waitForRequests(3);
      requests[2].reply.complete({'code': -403, 'message': '拒绝取消'});
      await deleting;
    });
    expect(controller.collection.tracking.value.result.data.followed, isTrue);
    expect(controller.collection.tracking.value.busy, isFalse);
    await finish(tester);
  });

  testWidgets('追番切号后的迟到写入成功不改变当前状态', (tester) async {
    await mount(tester);
    final controller = own(_Intro());
    await tester.runAsync(() async {
      final reading = controller.queryIsFollowed();
      await interceptor.waitForRequests(1);
      requests[0].reply.complete({
        'code': 0,
        'result': {'follow': 0},
      });
      await reading;
      final pending = controller.pgcAdd();
      await interceptor.waitForRequests(2);
      Accounts.accountMode[AccountType.main.index] = account(2);
      requests[1].reply.complete({'code': 0});
      await pending;
    });
    expect(controller.collection.tracking.value.result.data.followed, isFalse);
    expect(controller.collection.tracking.value.busy, isFalse);
    await finish(tester);
  });
}
