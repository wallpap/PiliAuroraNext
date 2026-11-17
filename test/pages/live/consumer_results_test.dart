import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/remote/live/live_danmaku/danmaku_msg.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/feedback.dart'
    as live_feedback;
import 'package:pili_aurora_next/pages/danmaku/danmaku_model.dart';
import 'package:pili_aurora_next/pages/live/widgets/live_item_app.dart';
import 'package:pili_aurora_next/pages/live_room/chat_buffer.dart';
import 'package:pili_aurora_next/pages/live_room/contribution_rank/controller.dart';
import 'package:pili_aurora_next/pages/live_room/controller.dart';
import 'package:pili_aurora_next/pages/live_room/widgets/chat_panel.dart';
import 'package:pili_aurora_next/pages/live_room/widgets/desktop_sidebar.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Room implements LiveRoomController {
  @override
  int roomId = 1;
  @override
  bool isClosed = false;
  @override
  bool autoScroll = false;
  @override
  final onlineCount = RxnString('12');
  @override
  final messages = Rx<List<LiveChatMessage<dynamic>>>([]);
  @override
  final chatBuffer = LiveChatBuffer<dynamic>();
  @override
  final historyTruncated = false.obs;
  @override
  final disableAutoScroll = false.obs;
  @override
  final unreadMessages = (0, 0).obs;
  @override
  final scrollController = ScrollController();
  @override
  bool get showSuperChat => false;
  @override
  void handleJumpToBottom() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  final controllers = <GetxController>[];
  late LoginAccount main;
  late LoginAccount recommend;
  LoginAccount account(int mid, [String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  T own<T extends GetxController>(T controller) {
    controllers.add(controller);
    return controller;
  }

  Map<String, dynamic> rank(String name) => {
    'code': 0,
    'data': {
      'item': [
        {'name': name},
      ],
    },
  };
  Map<String, dynamic> guard(String name) => {
    'code': 0,
    'data': {
      'info': {'num': 1},
      'top3': [
        {'username': name},
      ],
    },
  };
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
    ThemeUtils.darkTheme = ThemeData.dark();
  });
  setUp(() async {
    main = account(1, 'main');
    recommend = account(3, 'recommend');
    Accounts.accountMode[AccountType.main.index] = main;
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    await GStorage.localCache.putAll({
      LocalCacheKey.mixinKey: 'synthetic',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    Get.testMode = true;
    requests.clear();
  });
  tearDown(() {
    for (final controller in controllers.reversed) {
      if (!controller.isClosed) controller.onDelete();
    }
    controllers.clear();
    for (final request in requests) {
      if (!request.reply.isCompleted) {
        request.reply.complete({'code': -1, 'message': 'closed'});
      }
    }
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final deadline = tester.binding.clock.now().add(const Duration(seconds: 3));
    while (!condition() && tester.binding.clock.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
    await tester.pump();
  }

  Future<void> clearToasts(WidgetTester tester) async {
    final dismissal = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissal;
  }

  Future<void> mount(WidgetTester tester, Widget child) async {
    addTearDown(() async {
      await clearToasts(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: child),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
  }

  Future<void> finish(WidgetTester tester) async {
    await clearToasts(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  test('直播贡献榜固定主账号并丢弃旧凭据和关闭后的结果', () async {
    final controller = own(
      ContributionRankController(
        ruid: 2,
        roomId: 1,
        type: .online_rank,
      ),
    )..onInit();
    await interceptor.waitForRequests(1);
    final replacement = account(1, 'replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests.last.reply.complete(rank('当前观众'));
    await flush();
    requests.first.reply.complete(rank('旧观众'));
    await flush();
    expect(controller.loadingState.value.data!.single.name, '当前观众');
    final query = controller.onRefresh();
    await interceptor.waitForRequests(3);
    controller.onDelete();
    requests.last.reply.complete(rank('关闭后的观众'));
    await query;
    expect(controller.loadingState.value.data!.single.name, '当前观众');
    Accounts.replaceCredentials(account(1, 'closed'));
    expect(requests, hasLength(3));
  });

  testWidgets('直播侧栏切房清理旧榜单，舰长结果绑定房间和账号', (tester) async {
    final room = _Room();
    addTearDown(room.scrollController.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    Widget sidebar(int roomId) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 380,
          height: 600,
          child: DesktopLiveSidebar(
            roomId: roomId,
            anchorUid: roomId + 10,
            anchorName: '主播',
            liveRoomController: room,
            chat: const SizedBox.expand(),
            input: const SizedBox(height: 48),
            onShowRank: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(sidebar(1));
    await until(tester, () => requests.length == 2);
    expect(
      Get.isRegistered<ContributionRankController?>(tag: 'desktop-live-1'),
      isFalse,
    );
    final oldRank = Get.find<ContributionRankController>(tag: 'desktop-live-1');
    await tester.pumpWidget(sidebar(2));
    await until(tester, () => requests.length == 4);
    expect(oldRank.isClosed, isTrue);
    expect(
      Get.isRegistered<ContributionRankController>(tag: 'desktop-live-1'),
      isFalse,
    );
    for (final request in requests) {
      if (request.options.path == Api.liveContributionRank) {
        request.reply.complete(rank('观众'));
      } else if (request.options.queryParameters['roomid'] == 2) {
        request.reply.complete(guard('新舰长'));
      }
    }
    await tester.pump();
    await tester.tap(find.textContaining('大航海', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('新舰长'), findsOneWidget);
    final oldGuard = requests.firstWhere(
      (request) => request.options.path == Api.liveGuardTopList,
    );
    oldGuard.reply.complete(guard('旧舰长'));
    await tester.pumpAndSettle();
    expect(find.text('旧舰长'), findsNothing);
    Accounts.replaceCredentials(account(1, 'replacement'));
    await until(tester, () => requests.length == 6);
    for (final request in requests.skip(4)) {
      request.reply.complete(
        request.options.path == Api.liveGuardTopList
            ? guard('新账号舰长')
            : rank('新账号观众'),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('新账号舰长'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Accounts.replaceCredentials(account(1, 'closed'));
    expect(requests, hasLength(6));
    expect(
      Get.isRegistered<ContributionRankController>(tag: 'desktop-live-2'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('直播反馈只交付明确结果，重复点击和切号后成功不产生错误提示', (tester) async {
    final item = CardLiveItem(
      roomid: 1,
      title: '直播',
      uname: '主播',
      feedback: [
        live_feedback.Feedback(
          reasons: [
            live_feedback.Reason(id: 1, name: '不感兴趣', idType: 'room'),
          ],
        ),
      ],
    );
    await mount(
      tester,
      SizedBox(width: 300, height: 300, child: LiveCardVApp(item: item)),
    );
    Future<void> submit() async {
      await tester.tap(find.byIcon(Icons.more_vert_outlined));
      await tester.pumpAndSettle();
      final reason = tester.widget<SearchText>(find.byType(SearchText));
      reason.onTap!(reason.text);
      reason.onTap!(reason.text);
    }

    await submit();
    await until(tester, () => requests.length == 1);
    expect(requests.single.options.extra['account'], same(recommend));
    requests.single.reply.complete({'code': '0'});
    await tester.pumpAndSettle();
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);
    expect(find.text('提交成功'), findsNothing);
    await clearToasts(tester);
    await submit();
    await until(tester, () => requests.length == 2);
    Accounts.replaceCredentials(account(3, 'replacement'));
    requests.last.reply.complete({'code': 0});
    await tester.pumpAndSettle();
    expect(find.text('提交成功'), findsNothing);
    expect(find.text('正在提交'), findsNothing);
    await finish(tester);
  });

  testWidgets('直播屏蔽菜单绑定打开时账号和房间，旧操作不宣告成功', (tester) async {
    final room = _Room();
    addTearDown(room.scrollController.dispose);
    room.messages.value = [
      const LiveChatMessage(
        id: 1,
        content: DanmakuMsg(
          name: '发送者',
          text: '消息',
          extra: LiveDanmaku(id: '1', mid: 2, dmType: 0, ts: 0, ct: 0),
        ),
      ),
    ];
    await mount(
      tester,
      LiveRoomChatPanel(liveRoomController: room, isPP: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('发送者', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏蔽发送者'));
    await until(tester, () => requests.length == 1);
    expect(requests.single.options.extra['account'], same(main));
    expect((requests.single.options.data as Map)['roomid'], 1);
    room.roomId = 2;
    requests.single.reply.complete({
      'code': 0,
      'data': {'uid': 2, 'uname': '发送者'},
    });
    await tester.pumpAndSettle();
    expect(find.text('屏蔽成功'), findsNothing);
    await tester.tap(find.textContaining('发送者', findRichText: true));
    await tester.pumpAndSettle();
    Accounts.replaceCredentials(account(1, 'replacement'));
    await tester.tap(find.text('屏蔽发送者'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    await finish(tester);
  });
}
