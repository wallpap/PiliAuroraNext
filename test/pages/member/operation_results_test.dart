import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/data.dart';
import 'package:pili_aurora_next/pages/member/view.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

LoginAccount _login(String csrf) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
  null,
  null,
)..activated = true;

class _Accounts extends MainAccountNotifier {
  @override
  Account build() => _login('old');
  void replace() => state = _login('new');
}

class _Repository extends SpaceRepository {
  final writes = <(Account, int, int)>[];
  Completer<LoadingState<void>>? relationResponse;
  Completer<LoadingState<void>>? experienceResponse;
  final experienceAccounts = <Account>[];
  @override
  Future<LoadingState<SpaceData>> space(
    Account account,
    int mid,
    String? aid,
  ) async => Success(
    SpaceData.fromJson({
      'relation': 4,
      'card': {
        'name': 'UP主',
        'vip': {'status': 1},
        'relation': {'is_followed': 1},
      },
    }),
  );
  @override
  Future<LoadingState<void>> relation(
    Account account,
    int mid,
    int action,
  ) async {
    writes.add((account, mid, action));
    return await relationResponse?.future ?? const Success(null);
  }

  @override
  Future<LoadingState<void>> claimExperience(Account account) async {
    experienceAccounts.add(account);
    return await experienceResponse?.future ?? const Success(null);
  }
}

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late ProviderContainer container;

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
  });

  Future<void> mount(WidgetTester tester, {int mid = 2}) async {
    accounts = _Accounts();
    repository = _Repository();
    container = ProviderContainer.test(
      overrides: [
        mainAccountProvider.overrideWith(() => accounts),
        spaceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          initialRoute: '/member?mid=$mid',
          getPages: [GetPage(name: '/member', page: () => const MemberPage())],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String choice) async {
    await tester.tap(find.byType(PopupMenuButton<dynamic>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  }

  testWidgets('空间菜单的旧拉黑确认不写入新凭据，重新打开仍能提交', (tester) async {
    await mount(tester);
    await menu(tester, '加入黑名单');
    accounts.replace();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.writes, isEmpty);
    await menu(tester, '加入黑名单');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.writes.single, (
      container.read(mainAccountProvider),
      2,
      5,
    ));
    await tester.tap(find.byType(PopupMenuButton<dynamic>));
    await tester.pumpAndSettle();
    expect(find.text('移除黑名单'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('移除粉丝互斥，失败后保留菜单入口，成功才移除入口', (tester) async {
    await mount(tester);
    final failed = repository.relationResponse = Completer();
    await menu(tester, '移除粉丝');
    await menu(tester, '移除粉丝');
    expect(repository.writes.map((entry) => entry.$3), [7]);
    failed.complete(const Error('操作被拒绝'));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作被拒绝'), findsOneWidget);
    repository.relationResponse = null;
    await menu(tester, '移除粉丝');
    expect(repository.writes.map((entry) => entry.$3), [7, 7]);
    await tester.tap(find.byType(PopupMenuButton<dynamic>));
    await tester.pumpAndSettle();
    expect(find.text('移除粉丝'), findsNothing);
    await finish(tester);
  });

  testWidgets('大会员经验固定提交凭据，重复点击不发送，换凭据后不报旧成功', (tester) async {
    await mount(tester, mid: 1);
    final original = container.read(mainAccountProvider);
    final pending = repository.experienceResponse = Completer();
    await menu(tester, '大会员经验');
    await menu(tester, '大会员经验');
    expect(repository.experienceAccounts, [same(original)]);
    accounts.replace();
    await tester.pumpAndSettle();
    pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(find.text('领取成功'), findsNothing);
    await finish(tester);
  });
}
