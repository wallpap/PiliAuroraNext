import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/community/domain/vote.dart'
    show VoteInfo, Option;
import 'package:pili_aurora_next/pages/dynamics/widgets/additional_panel.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/action_panel.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/vote.dart';
import 'package:pili_aurora_next/pages/dynamics_detail/controller.dart';
import 'package:pili_aurora_next/pages/dynamics_detail/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  Account account(int id) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': 'fixture-$id'}),
    null,
    null,
  );
  final original = account(1);
  final replacement = account(2);
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
    Accounts.accountMode[AccountType.main.index] = original;
    requests.clear();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  Future<void> mount(WidgetTester tester, [Widget? child]) async {
    addTearDown(() async {
      final dismissal = SmartDialog.dismiss(status: .allToast);
      await tester.pumpAndSettle();
      await dismissal;
    });
    await tester.pumpWidget(
      ProviderScope(
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: Scaffold(body: child ?? const SizedBox()),
        ),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
    await tester.pump();
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final end = tester.binding.clock.now().add(const Duration(seconds: 3));
    while (!condition() && tester.binding.clock.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    final dismissal = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissal;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  DynamicItemModel item() => DynamicItemModel.fromJson({
    'id_str': '1',
    'modules': {
      'module_author': {
        'icon_badge': {'text': '仅自己可见'},
      },
      'module_stat': {
        'forward': {'count': 0},
        'comment': {'count': 0},
        'like': {'status': true, 'count': 0},
      },
    },
  });

  testWidgets('再次打开同一动态显示新页面的内容，返回后保留原详情', (tester) async {
    await mount(tester);

    void open(String author) {
      final dynamic = DynamicItemModel.fromJson({
        'id_str': '1',
        'modules': {
          'module_author': {'name': author, 'mid': 1},
        },
      });
      Get.to(
        () => const DynamicDetailPage(),
        arguments: {'item': dynamic},
        preventDuplicates: false,
      );
    }

    open('首次打开的动态作者');
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete({'code': -404, 'message': '原评论来源不可用'});
    await settle(tester);
    expect(find.text('首次打开的动态作者'), findsWidgets);

    open('再次打开的动态作者');
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({'code': -404, 'message': '新评论来源不可用'});
    await settle(tester);
    expect(find.text('再次打开的动态作者'), findsWidgets);
    expect(find.text('首次打开的动态作者'), findsNothing);

    Get.back();
    await settle(tester);
    expect(find.text('首次打开的动态作者'), findsWidgets);
    await finish(tester);
  });

  testWidgets('同一动态的独立卡片共用点赞锁，待确认和凭据替换保留原计数', (tester) async {
    final dynamic = item();
    await mount(
      tester,
      Column(
        children: [
          ActionPanel(item: dynamic),
          ActionPanel(item: item()),
        ],
      ),
    );
    Finder likeButton(int index) => find
        .descendant(
          of: find.byType(ActionPanel).at(index),
          matching: find.byType(TextButton),
        )
        .last;
    Finder icon(int index) => find.descendant(
      of: likeButton(index),
      matching: find.byType(Icon),
    );
    await tester.tap(likeButton(0));
    await until(tester, () => requests.length == 1);
    await tester.tap(likeButton(1));
    await tester.pump();
    expect(requests, hasLength(1));
    requests[0].reply.complete({'code': '0'});
    await settle(tester);
    expect(tester.widget<Icon>(icon(0)).semanticLabel, '已赞');
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);
    await tester.tap(likeButton(0));
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({'code': 0});
    await settle(tester);
    expect(tester.widget<Icon>(icon(0)).semanticLabel, '点赞');
    expect(
      find.descendant(of: likeButton(0), matching: find.text('0')),
      findsOneWidget,
    );
    await tester.tap(likeButton(0));
    await until(tester, () => requests.length == 3);
    Accounts.accountMode[AccountType.main.index] = account(original.mid);
    requests[2].reply.complete({'code': 0});
    await settle(tester);
    expect(tester.widget<Icon>(icon(0)).semanticLabel, '点赞');
    expect(
      requests.every(
        (request) => identical(request.options.extra['account'], original),
      ),
      isTrue,
    );
    await finish(tester);
  });

  testWidgets('重新打开动态仍共用可见范围写入锁，待确认和迟到成功不更新标签', (tester) async {
    await mount(tester);
    final dynamic = item();
    final details = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    ).read(dynamicDetailsProvider);
    final controller = DynamicDetailController(details)..dynItem = dynamic;
    addTearDown(controller.onDelete.call);
    final pending = controller.onSetPubSetting(true, '1');
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete({'code': '0'});
    await settle(tester);
    expect(await pending, isA<UnknownResult>());
    expect(dynamic.modules.moduleAuthor!.badgeText, '仅自己可见');
    final stale = controller.onSetPubSetting(true, '1');
    await until(tester, () => requests.length == 2);
    controller.onDelete();
    final reopened = DynamicDetailController(details)..dynItem = item();
    addTearDown(reopened.onDelete.call);
    expect(await reopened.onSetPubSetting(true, '1'), isA<Error>());
    expect(requests, hasLength(2));
    requests[1].reply.complete({'code': 0});
    await settle(tester);
    expect(await stale, isA<Error>());
    expect(dynamic.modules.moduleAuthor!.badgeText, '仅自己可见');
    await finish(tester);
  });

  testWidgets('投票提交冻结选项并处理回调异常，切号后的成功不消费', (tester) async {
    final info = VoteInfo(
      title: '投票',
      voteId: 7,
      choiceCnt: 1,
      endTime:
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000,
      options: [
        Option.fromJson({'opt_idx': 1, 'opt_desc': '甲'}),
        Option.fromJson({'opt_idx': 2, 'opt_desc': '乙'}),
      ],
    );
    var calls = 0;
    final reply = Completer<LoadingState<VoteInfo>>();
    await mount(
      tester,
      SizedBox(
        height: 450,
        child: VotePanel(
          voteInfo: info,
          onVote: (votes, anonymous) {
            calls++;
            expect(votes, {1});
            if (calls == 1) throw StateError('fixture');
            return reply.future;
          },
        ),
      ),
    );
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete({'code': 0});
    await settle(tester);
    await tester.tap(find.text('甲'));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton));
    await settle(tester);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(calls, 2);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('乙'));
    await tester.pump();
    Accounts.accountMode[AccountType.main.index] = replacement;
    reply.complete(Success(info));
    await settle(tester);
    expect(find.text('账号已切换，请重新打开投票'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
    await finish(tester);
  });

  testWidgets('预约防重复提交，可选回执缺失保留旧数据，切号不回写', (tester) async {
    final reserve = Reserve(
      title: '预约',
      rid: 7,
      reserveTotal: 8,
      desc2: Desc(text: '已有八人预约'),
      button: ReserveBtn(status: 0, type: 1),
    );
    await mount(
      tester,
      Builder(
        builder: (context) => addWidget(
          context,
          floor: 1,
          theme: Theme.of(context),
          idStr: '1',
          additional: DynamicAddModel(
            type: 'ADDITIONAL_TYPE_RESERVE',
            reserve: reserve,
          ),
        )!,
      ),
    );
    await tester.tap(find.text('预约').last);
    await until(tester, () => requests.length == 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    requests[0].reply.complete({
      'code': 0,
      'data': {'final_btn_status': 1},
    });
    await settle(tester);
    expect(reserve.button!.status, 1);
    expect(reserve.reserveTotal, 8);
    expect(reserve.desc2!.text, '已有八人预约');
    await tester.tap(find.text('已预约'));
    await until(tester, () => requests.length == 2);
    Accounts.accountMode[AccountType.main.index] = replacement;
    requests[1].reply.complete({
      'code': 0,
      'data': {'final_btn_status': 0, 'reserve_update': 0},
    });
    await settle(tester);
    expect(reserve.button!.status, 1);
    expect(reserve.reserveTotal, 8);
    await finish(tester);
  });
}
