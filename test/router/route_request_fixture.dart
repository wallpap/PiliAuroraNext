import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../support/controlled_interceptor.dart';
import '../support/memory_box.dart';

class RouteRequestFixture {
  RouteRequestFixture({String? redirectTo})
    : _interceptor = ControlledInterceptor(
        headers: redirectTo == null
            ? null
            : Headers.fromMap({
                'location': [redirectTo],
              }),
      ) {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() {
      GStorage.setting = MemoryBox();
      GStorage.video = MemoryBox();
      GStorage.localCache = MemoryBox();
      Request();
      Request.dio.interceptors
        ..clear()
        ..add(_interceptor);
    });
    setUp(() {
      Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
      requests.clear();
      openedVideos.clear();
    });
    tearDown(Get.reset);
    tearDownAll(() async {
      Request.dio.close(force: true);
      await _interceptor.close();
    });
  }

  final ControlledInterceptor _interceptor;
  List<({RequestOptions options, Completer<dynamic> reply})> get requests =>
      _interceptor.requests;
  final openedVideos = <Map>[];

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    GetMaterialApp(
      builder: FlutterSmartDialog.init(),
      navigatorObservers: [routeObserver, FlutterSmartDialog.observer],
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/',
          page: () => const Scaffold(body: Text('来源页面')),
        ),
        GetPage(
          name: '/videoV',
          page: () {
            openedVideos.add(Get.arguments as Map);
            return const Scaffold(body: Text('视频页面'));
          },
        ),
        GetPage(
          name: '/other',
          page: () => const Scaffold(body: Text('其他页面')),
        ),
      ],
    ),
  );
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final deadline = tester.binding.clock.now().add(const Duration(seconds: 3));
    while (!ready() && tester.binding.clock.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(ready(), true);
  }

  Future<void> complete(
    WidgetTester tester,
    Future<void> operation,
    int index,
    Object body,
  ) async {
    var done = false;
    unawaited(operation.whenComplete(() => done = true));
    requests[index].reply.complete(body);
    await until(tester, () => done);
    await operation;
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> finish(WidgetTester tester) async {
    final dismiss = SmartDialog.dismiss(status: SmartStatus.allDialog);
    await tester.pumpAndSettle();
    await dismiss;
    final toasts = SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pumpAndSettle();
    await toasts;
    await tester.pumpWidget(const SizedBox());
  }
}
