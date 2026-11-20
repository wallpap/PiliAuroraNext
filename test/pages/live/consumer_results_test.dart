import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/playback/domain/live/chat/danmaku_msg.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/feedback.dart'
    as live_feedback;
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/pages/live/widgets/live_item_app.dart';
import 'package:pili_aurora_next/pages/live_room/chat_buffer.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_interactions.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_rankings.dart';
import 'package:pili_aurora_next/pages/live_room/controller.dart';
import 'package:pili_aurora_next/pages/live_room/widgets/chat_panel.dart';
import 'package:pili_aurora_next/pages/live_room/widgets/desktop_sidebar.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
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
  final onlineCount = ValueNotifier<String?>('12');
  @override
  final ValueNotifier<
    ({List<LiveChatMessage<dynamic>> messages, bool truncated})
  >
  chatHistory =
      ValueNotifier<
        ({List<LiveChatMessage<dynamic>> messages, bool truncated})
      >((messages: const [], truncated: false));
  @override
  final chatBuffer = LiveChatBuffer<dynamic>();
  @override
  final disableAutoScroll = ValueNotifier(false);
  @override
  final unreadMessages = ValueNotifier((0, 0));
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
  late LoginAccount main;
  late LoginAccount recommend;
  LoginAccount account(int mid, [String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
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
    final container = ProviderContainer.test();
    final provider = liveContributionProvider((
      (scope: Object(), room: 1, anchor: 2),
      .online_rank,
    ));
    final names = <String?>[];
    final subscription = container.listen(provider, (_, next) {
      if (next is AsyncData && !next.isLoading) {
        names.add(next.requireValue.dataOrNull?.single.name);
      }
    });
    await interceptor.waitForRequests(1);
    final replacement = account(1, 'replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests.last.reply.complete(rank('当前观众'));
    await flush();
    requests.first.reply.complete(rank('旧观众'));
    await flush();
    expect(names, ['当前观众']);
    container.invalidate(provider);
    await interceptor.waitForRequests(3);
    subscription.close();
    await container.pump();
    requests.last.reply.complete(rank('关闭后的观众'));
    await flush();
    expect(names, ['当前观众']);
    Accounts.replaceCredentials(account(1, 'closed'));
    expect(requests, hasLength(3));
  });

  testWidgets('直播点赞分批结算，不清空在途期间的新点击或提交已失效批次', (tester) async {
    final previousHeartbeat = Accounts.heartbeat;
    Accounts.accountMode[AccountType.heartbeat.index] = main;
    addTearDown(
      () =>
          Accounts.accountMode[AccountType.heartbeat.index] = previousHeartbeat,
    );
    var count = 0;
    final receipts = <bool>[];
    final likes = LiveRoomLikes(
      room: () => 1,
      anchor: () => 9,
      onCount: (value) => count = value,
      onReceipt: (result) => receipts.add(result.isSuccess),
    );
    addTearDown(likes.dispose);
    Future<void> click() async {
      likes
        ..tapDown()
        ..tapUp();
      await tester.pump(const Duration(milliseconds: 800));
    }

    await click();
    await until(tester, () => requests.length == 1);
    await click();
    expect(requests, hasLength(1));
    requests.first.reply.complete({'code': 0});
    await until(tester, () => requests.length == 2);
    expect(count, 1);
    expect(requests.map((request) => request.options.data['click_time']), [
      1,
      1,
    ]);
    likes
      ..tapDown()
      ..tapUp();
    Accounts.accountMode[AccountType.main.index] = account(
      1,
      'new-credentials',
    );
    requests.last.reply.complete({'code': 0});
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(receipts, [true]);
    expect(count, 0);
    expect(requests, hasLength(2));
  });

  testWidgets('直播侧栏切房清理旧榜单，舰长结果绑定房间和账号', (tester) async {
    final room = _Room();
    addTearDown(room.scrollController.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    Widget sidebar(int roomId) => ProviderScope(
      child: MaterialApp(
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
      ),
    );
    await tester.pumpWidget(sidebar(1));
    await until(tester, () => requests.length == 2);
    await tester.pumpWidget(sidebar(2));
    await until(tester, () => requests.length == 4);
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
    room.chatHistory.value = (
      messages: const [
        LiveChatMessage(
          id: 1,
          content: DanmakuMsg(
            name: '发送者',
            text: '消息',
            extra: LiveDanmaku(id: '1', mid: 2, dmType: 0, ts: 0, ct: 0),
          ),
        ),
      ],
      truncated: false,
    );
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
