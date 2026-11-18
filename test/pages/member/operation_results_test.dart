import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/space/space/data.dart';
import 'package:pili_aurora_next/pages/member/view.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
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
    return const Success(null);
  }
}

void main() {
  testWidgets('空间菜单的旧拉黑确认不写入新凭据，重新打开仍能提交', (tester) async {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    final accounts = _Accounts();
    final repository = _Repository();
    final container = ProviderContainer.test(
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
          initialRoute: '/member?mid=2',
          getPages: [GetPage(name: '/member', page: () => const MemberPage())],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openConfirmation() async {
      await tester.tap(find.byType(PopupMenuButton<dynamic>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入黑名单'));
      await tester.pumpAndSettle();
    }

    await openConfirmation();
    accounts.replace();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.writes, isEmpty);
    await openConfirmation();
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
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
