import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart';
import 'package:pili_aurora_next/pages/common/publish/common_rich_text_pub_page.dart';
import 'package:pili_aurora_next/pages/dynamics_create/view.dart';
import 'package:pili_aurora_next/features/community/application/reserve_editor.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/vote_editor.dart';
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/community/presentation/dynamic_visibility_check.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../common/publish/upload_fixture.dart';
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
  late Directory directory;
  late File image;
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    GStorage.userInfo = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
    directory = await Directory.systemTemp.createTemp('pili-publish-');
    image = await File('${directory.path}/pixel.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
  });
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = original;
    requests.clear();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
    await image.delete();
    await directory.delete();
  });

  Future<void> mount(WidgetTester tester, [Widget? panel]) async {
    addTearDown(() async {
      final dismissal = SmartDialog.dismiss(status: .allToast);
      await tester.pumpAndSettle();
      await dismissal;
    });
    await tester.pumpWidget(
      ProviderScope(
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const Scaffold(body: Text('原页面')),
        ),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
    if (panel != null) {
      Get.to(() => Scaffold(body: panel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
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

  ({ProviderContainer container, VoteEditor editor, VoteEditorQuery query})
  voteEditor(int? id) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final query = (owner: Object(), id: id);
    container.listen(voteEditorProvider(query), (_, _) {});
    return (
      container: container,
      editor: container.read(voteEditorProvider(query).notifier),
      query: query,
    );
  }

  ({
    ProviderContainer container,
    ReserveEditor editor,
    ReserveEditorQuery query,
  })
  reserveEditor(int? id) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final query = (owner: Object(), id: id);
    container.listen(reserveEditorProvider(query), (_, _) {});
    return (
      container: container,
      editor: container.read(reserveEditorProvider(query).notifier),
      query: query,
    );
  }

  testWidgets('动态发布在图片上传前固定草稿，成功保留新草稿且阻止并发提交', (tester) async {
    var saved = 0;
    await mount(
      tester,
      CreateDynPanel(
        onSuccess: () {
          saved++;
          throw StateError('fixture callback');
        },
      ),
    );
    final state = tester.state<CommonRichTextPubPageState>(
      find.byType(CreateDynPanel),
    );
    state.editController.text = '原草稿';
    state.addDraftImage(FilePicModel(path: image.path));
    final submission = await reachPublishRequest(
      tester,
      interceptor: interceptor,
      publish: state.onPublish,
      replaceDraft: () {
        state.editController.text = '新草稿';
        state.removeDraftImage(0);
      },
    );
    final body = submission.request.data as Map;
    expect(body['dyn_req']['content']['contents'].first['raw_text'], '原草稿');
    expect(body['dyn_req']['pics'], hasLength(1));
    await tester.runAsync(() async {
      requests[1].reply.complete({'code': 0});
      await submission.completion;
    });
    await settle(tester);
    expect(saved, 1);
    expect(state.editController.text, '新草稿');
    expect(state.hasPub, isFalse);
    expect(find.byType(CreateDynPanel), findsOneWidget);
    expect(find.text('发布成功，已保留新草稿'), findsOneWidget);
    expect(find.text('发布准备失败，请重试'), findsNothing);
    await finish(tester);
  });

  testWidgets('动态上传后切号不继续发布，待确认保留草稿并释放提交状态', (tester) async {
    await mount(tester, const CreateDynPanel());
    final state = tester.state<CommonRichTextPubPageState>(
      find.byType(CreateDynPanel),
    );
    state.editController.text = '草稿';
    state.addDraftImage(FilePicModel(path: image.path));
    late Future<void> uploading;
    await tester.runAsync(() async {
      uploading = state.onPublish();
      await interceptor.waitForRequests(1);
    });
    Accounts.accountMode[AccountType.main.index] = replacement;
    await tester.runAsync(() async {
      requests[0].reply.complete(uploadedPicture());
      await uploading;
    });
    await settle(tester);
    expect(requests, hasLength(1));
    state.removeDraftImage(0);
    final saving = state.onPublish();
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({'code': '0'});
    await settle(tester);
    await saving;
    expect(state.editController.text, '草稿');
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);
    expect(find.text('发布中'), findsNothing);
    await finish(tester);
  });

  testWidgets('转发成功和迟到失败不会关闭之后打开的页面', (tester) async {
    await mount(tester, const RepostPanel(dynIdStr: '1'));
    final panel = find.byType(RepostPanel);
    final container = ProviderScope.containerOf(tester.element(panel));
    final notifications = <DynamicsChange>[];
    final subscription = container
        .read(dynamicsUpdatesProvider)
        .changes
        .listen(notifications.add);
    addTearDown(subscription.cancel);
    final state = tester.state<CommonRichTextPubPageState>(panel);
    state.editController.text = '转发内容';
    final pending = state.onPublish();
    await until(tester, () => requests.length == 1);
    Get.to(() => const Scaffold(body: Text('新页面')), preventDuplicates: false);
    await settle(tester);
    requests[0].reply.complete({'code': 0});
    await settle(tester);
    await pending;
    expect(find.text('新页面'), findsOneWidget);
    expect(notifications.map((event) => event.account), [original]);
    Get.back();
    await settle(tester);
    final second = state.onPublish();
    await until(tester, () => requests.length == 2);
    Accounts.accountMode[AccountType.main.index] = replacement;
    requests[1].reply.complete({'code': -403, 'message': '旧转发失败'});
    await settle(tester);
    await second;
    expect(find.text('旧转发失败'), findsNothing);
    await finish(tester);
  });

  test('动态失效事件按应用作用域隔离，释放后忽略迟到通知', () async {
    final closedScope = ProviderContainer.test();
    final activeScope = ProviderContainer.test();
    final closedUpdates = closedScope.read(dynamicsUpdatesProvider);
    final activeUpdates = activeScope.read(dynamicsUpdatesProvider);
    final closedEvents = <DynamicsChange>[];
    final activeEvents = <DynamicsChange>[];
    final closedSubscription = closedUpdates.changes.listen(closedEvents.add);
    final activeSubscription = activeUpdates.changes.listen(activeEvents.add);
    addTearDown(closedSubscription.cancel);
    addTearDown(activeSubscription.cancel);
    final completed = closedSubscription.asFuture<void>();

    closedUpdates.removed(original, '1');
    closedScope.dispose();
    closedUpdates.removed(original, '2');
    activeUpdates.removed(original, '3');
    await completed;

    expect(closedEvents.map((event) => event.removed), ['1']);
    expect(activeEvents.map((event) => event.removed), ['3']);
  });

  testWidgets('投票保存互斥并返回提交时的选项副本，待确认后允许核对再操作', (tester) async {
    await mount(tester);
    final fixture = voteEditor(null);
    final controller = fixture.editor
      ..update((draft) => draft.copy(title: '原标题'));
    final options = fixture.container
        .read(voteEditorProvider(fixture.query))
        .draft
        .options;
    controller
      ..optionText(options[0].id, '甲')
      ..optionText(options[1].id, '乙');
    final pending = controller.onCreate();
    expect(await controller.onCreate(), isA<Error>());
    await until(tester, () => requests.length == 1);
    controller
      ..update((draft) => draft.copy(title: '新标题'))
      ..optionText(options[0].id, '新选项');
    requests[0].reply.complete({
      'code': 0,
      'data': {'vote_id': 7},
    });
    await settle(tester);
    final result = await pending;
    expect(result.data.title, '原标题');
    expect(result.data.options.first.optDesc, '甲');
    expect(result.data.voteId, 7);
    expect(
      fixture.container.read(voteEditorProvider(fixture.query)).draft.title,
      '新标题',
    );
    expect(controller.voteId, 7);
    final retry = controller.onCreate();
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({'code': '0'});
    await settle(tester);
    expect(await retry, isA<UnknownResult>());
    expect(
      fixture.container.read(voteEditorProvider(fixture.query)).saving,
      isFalse,
    );
    await finish(tester);
  });

  testWidgets('预约保存返回提交快照，切号或关闭后不交付旧成功结果', (tester) async {
    await mount(tester);
    final fixture = reserveEditor(null);
    final controller = fixture.editor
      ..update((draft) => draft.copy(title: '原预约', subType: 1));
    final pending = controller.onCreate();
    expect(await controller.onCreate(), isA<Error>());
    await until(tester, () => requests.length == 1);
    controller.update((draft) => draft.copy(title: '新预约'));
    requests[0].reply.complete({
      'code': 0,
      'data': {'sid': 7},
    });
    await settle(tester);
    expect((await pending).data.title, '原预约');
    expect(requests[0].options.extra['account'], same(original));
    expect((requests[0].options.data as Map)['sub_type'], 1);
    final stale = controller.onCreate();
    await until(tester, () => requests.length == 2);
    expect(requests[1].options.path, Api.updateReserve);
    expect((requests[1].options.data as Map)['id'], 7);
    fixture.container.dispose();
    requests[1].reply.complete({
      'code': 0,
      'data': {'sid': 8},
    });
    await settle(tester);
    expect(await stale, isA<Error>());
    final switched = voteEditor(null).editor;
    Accounts.accountMode[AccountType.main.index] = replacement;
    expect(await switched.onCreate(), isA<Error>());
    expect(requests, hasLength(2));
    await finish(tester);
  });

  testWidgets('投票与预约详情失败可重试，关闭后拒绝迟到的必需字段', (tester) async {
    await mount(tester);
    final voteFixture = voteEditor(7);
    final vote = voteFixture.editor;
    final voteProvider = voteEditorProvider(voteFixture.query);
    final reserveFixture = reserveEditor(8);
    final reserve = reserveFixture.editor;
    final reserveProvider = reserveEditorProvider(reserveFixture.query);
    await until(tester, () => requests.length == 2);
    for (final request in requests) {
      request.reply.complete({'code': -403, 'message': '加载失败'});
    }
    await settle(tester);
    expect(voteFixture.container.read(voteProvider).error?.code, -403);
    expect(reserveFixture.container.read(reserveProvider).error?.code, -403);
    expect(vote.canCreate, isFalse);
    expect(reserve.canCreate, isFalse);
    final retry = reserve.queryData();
    await until(tester, () => requests.length == 3);
    requests[2].reply.complete({
      'code': 0,
      'data': {'id': 8, 'title': '预约', 'live_plan_start_time': 1900000000},
    });
    await settle(tester);
    await retry;
    expect(reserveFixture.container.read(reserveProvider).draft.title, '预约');
    expect(reserve.canCreate, isTrue);
    final stale = vote.queryData();
    await until(tester, () => requests.length == 4);
    voteFixture.container.dispose();
    requests[3].reply.complete({'code': -403, 'message': '旧错误'});
    await settle(tester);
    await stale;
    expect(vote.isCurrent, isFalse);
    reserveFixture.container.dispose();
    await finish(tester);
  });

  testWidgets('动态可见性查询故障只报告无法确认，不误报仅自己可见', (tester) async {
    await mount(tester);
    final pending = checkPublishedDynamic(id: '1', isManual: true);
    await until(tester, () => requests.length == 1);
    requests.single.reply.complete({'code': -500, 'message': '服务暂不可用'});
    await settle(tester);
    await pending;
    expect(find.textContaining('暂时无法确认动态可见性'), findsOneWidget);
    expect(find.textContaining('shadow ban'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await finish(tester);
  });
}
