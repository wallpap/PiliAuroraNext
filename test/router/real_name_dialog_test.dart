import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/presentation/real_name_dialog.dart';

import 'route_request_fixture.dart';

void main() {
  final fixture = RouteRequestFixture();
  final requests = fixture.requests;
  const failed = {'code': -404, 'message': '迟到错误'};

  testWidgets('实名查询只交付最近操作，当前成功可关闭弹窗', (tester) async {
    await fixture.mount(tester);
    final first = RealNameDialog.show('1');
    await fixture.until(tester, () => requests.length == 1);
    final latest = RealNameDialog.show('2');
    await fixture.until(tester, () => requests.length == 2);
    await fixture.complete(tester, first, 0, failed);
    expect(find.text('迟到错误'), findsNothing);
    await fixture.complete(tester, latest, 1, {
      'code': 0,
      'data': {'name': '当前实名'},
    });
    expect(find.text('当前实名'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsNothing);
    expect(find.text('来源页面'), findsOneWidget);
    await fixture.finish(tester);
  });

  testWidgets('实名查询离页再返回后丢弃迟到成功', (tester) async {
    await fixture.mount(tester);
    final operation = RealNameDialog.show('1');
    await fixture.until(tester, () => requests.length == 1);
    Get.toNamed<void>('/other');
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    await fixture.complete(tester, operation, 0, {
      'code': 0,
      'data': {'name': '旧页面实名'},
    });
    expect(find.text('旧页面实名'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await fixture.finish(tester);
  });

  testWidgets('实名查询账号替换后不显示旧响应', (tester) async {
    await fixture.mount(tester);
    final account = Accounts.main;
    final operation = RealNameDialog.show('1');
    await fixture.until(tester, () => requests.length == 1);
    expect(requests.single.options.extra['account'], same(account));
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '2', 'bili_jct': 'fixture'}),
      null,
      null,
    );
    await fixture.complete(tester, operation, 0, failed);
    expect(find.text('迟到错误'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await fixture.finish(tester);
  });
}
