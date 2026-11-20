import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/pages/member_dynamics/view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_actions.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_feed.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/application/member_dynamics.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/dynamics_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account([String csrf = 'fixture', int mid = 1]) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  late ProviderContainer container;
  late DynamicsUpdates updates;
  late LoginAccount original;
  final query = (owner: Object(), mid: 1);
  final provider = memberDynamicsProvider(query);
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, dynamic> page(
    List<String> ids,
    String cursor, {
    bool more = true,
  }) => {
    'code': 0,
    'data': {
      'has_more': more,
      'offset': cursor,
      'items': [
        for (final id in ids) {'id_str': id},
      ],
    },
  };
  Future<MemberDynamics> start() async {
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(page(['1', '2', '3'], 'a'));
    await tick();
    return container.read(provider.notifier);
  }

  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() async {
    requests.clear();
    original = account();
    Accounts.accountMode[AccountType.main.index] = original;
    Accounts.accountMode[AccountType.recommend.index] = account('recommend', 2);
    await GStorage.localCache.putAll({
      LocalCacheKey.mixinKey: 'synthetic',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    updates = DynamicsUpdates();
    container = ProviderContainer(
      overrides: [dynamicsUpdatesProvider.overrideWithValue(updates)],
    );
  });
  tearDown(() async {
    container.dispose();
    for (final request in requests) {
      if (!request.reply.isCompleted) request.reply.complete({'code': -1});
    }
    await tick();
    await updates.close();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('空间动态按页面与凭据隔离，推荐角色不重建查询，释放后不再请求', () async {
    final subscription = container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    final replacement = account('replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests[1].options.extra['account'], same(replacement));
    requests[1].reply.complete(page(['2'], 'new'));
    await tick();
    requests[0].reply.complete(page(['1'], 'old'));
    await tick();
    expect(container.read(provider).loading.data.single.idStr, '2');
    final source = container.read(provider).source;
    Accounts.accountMode[AccountType.recommend.index] = account('other');
    expect(container.read(provider).source, same(source));
    subscription.close();
    await container.pump();
    Accounts.replaceCredentials(account('closed'));
    await tick();
    expect(requests, hasLength(2));
  });

  test('分页互斥、失败重试原游标、去重与重复游标结束', () async {
    final notifier = await start();
    var pending = notifier.onLoadMore();
    await notifier.onLoadMore();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -403, 'message': '分页失败'});
    await pending;
    expect(container.read(provider).error?.errMsg, '分页失败');
    expect(container.read(provider).metadata?.offset, 'a');
    await notifier.onLoadMore();
    expect(requests, hasLength(2));
    pending = notifier.retry();
    await interceptor.waitForRequests(3);
    expect(requests[2].options.queryParameters['offset'], 'a');
    requests[2].reply.complete(page(['3', '4', '4'], 'a'));
    await pending;
    expect(container.read(provider).loading.data.map((item) => item.idStr), [
      '1',
      '2',
      '3',
      '4',
    ]);
    expect(container.read(provider).hasMore, isFalse);
  });

  test('连续无增长补读有预算并提供显式继续入口', () async {
    final notifier = await start();
    final pending = notifier.onLoadMore();
    for (var i = 1; i <= 5; i++) {
      await interceptor.waitForRequests(i + 1);
      requests[i].reply.complete(page(['1'], 'cursor-$i'));
    }
    await pending;
    expect(requests, hasLength(6));
    expect(container.read(provider).canLoadMore, isFalse);
    expect(container.read(provider).error, isNotNull);
    final retry = notifier.retry();
    await interceptor.waitForRequests(7);
    expect(requests.last.options.queryParameters['offset'], 'cursor-5');
    requests.last.reply.complete(page(['4'], '', more: false));
    await retry;
    expect(container.read(provider).loading.data.last.idStr, '4');
  });

  test('刷新保留已确认内容，旧分页失败不污染新查询，旧确认回调失效', () async {
    final notifier = await start();
    final item = container.read(provider).loading.data.first;
    final source = container.read(provider).source;
    final current = notifier.captureItem(item);
    final old = notifier.onLoadMore();
    await interceptor.waitForRequests(2);
    final refresh = notifier.onRefresh();
    await interceptor.waitForRequests(3);
    expect(container.read(provider).loading.data, hasLength(3));
    expect(current(), isFalse);
    expect(await notifier.removeItem(item, source), isA<Error>());
    requests[2].reply.complete(page(['4'], '', more: false));
    await refresh;
    requests[1].reply.complete({'code': -403, 'message': '旧分页失败'});
    await old;
    expect(container.read(provider).error, isNull);
    expect(container.read(provider).loading.data.single.idStr, '4');
  });

  test('删除共享锁跨空间与首页生效，待确认不移除，确认后同步各入口并排除迟到页', () async {
    final notifier = await start();
    final feed = dynamicsFeedProvider((
      owner: Object(),
      type: DynamicsTabType.all,
      hostMid: -1,
    ));
    container.listen(feed, (_, _) {});
    await interceptor.waitForRequests(2);
    final items = container.read(provider).loading.data;
    final source = container.read(provider).source;
    var pending = notifier.removeItem(items.first, source);
    await interceptor.waitForRequests(3);
    expect(requests[2].options.path, Api.removeDynamic);
    expect(requests[2].options.extra['account'], same(original));
    expect(
      await container.read(dynamicsActionsProvider).remove(original, '1'),
      isA<Error>(),
    );
    requests[2].reply.complete({'code': '0'});
    expect(await pending, isA<UnknownResult>());
    expect(container.read(provider).loading.data, hasLength(3));
    pending = notifier.removeItem(items.first, source);
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': 0});
    expect((await pending).isSuccess, isTrue);
    requests[1].reply.complete(page(['1', '4'], '', more: false));
    await tick();
    expect(container.read(feed).loading.data.single.idStr, '4');
    final more = notifier.onLoadMore();
    await interceptor.waitForRequests(5);
    requests[4].reply.complete(page(['1', '4'], '', more: false));
    await more;
    expect(container.read(provider).loading.data.map((item) => item.idStr), [
      '2',
      '3',
      '4',
    ]);
  });

  test('置顶与删除互斥，确认后所有空间快照同步且保留普通标签', () async {
    final notifier = await start();
    final other = memberDynamicsProvider((owner: Object(), mid: 1));
    container.listen(other, (_, _) {});
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'has_more': false,
        'items': [
          {
            'id_str': '1',
            'modules': {
              'module_tag': {'text': '普通标签'},
            },
          },
          {
            'id_str': '2',
            'modules': {
              'module_tag': {'text': '置顶'},
            },
          },
          {'id_str': '3'},
        ],
      },
    });
    await tick();
    final items = container.read(provider).loading.data;
    final source = container.read(provider).source;
    final pending = notifier.setPinned(items.last, source, false);
    await interceptor.waitForRequests(3);
    expect(await notifier.removeItem(items.first, source), isA<Error>());
    expect(await notifier.setPinned(items.last, source, false), isA<Error>());
    requests[2].reply.complete({'code': 0});
    expect((await pending).isSuccess, isTrue);
    expect(container.read(provider).loading.data.first.idStr, '3');
    final otherItems = container.read(other).loading.data;
    expect(otherItems.map((item) => item.idStr), ['3', '1', '2']);
    expect(otherItems[1].modules.moduleTag?.text, '普通标签');
    expect(otherItems[2].modules.moduleTag, isNull);
    expect(await notifier.setPinned(items.last, source, false), isA<Error>());
    final unpin = notifier.setPinned(items.last, source, true);
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': 0});
    await unpin;
    expect(
      container.read(provider).loading.data.first.isPinned,
      isFalse,
    );
  });

  test('另一空间尚未加载的置顶目标在续页回到首位，取消后迟到旧置顶不复活，刷新重新核对', () async {
    final notifier = await start();
    final other = memberDynamicsProvider((owner: Object(), mid: 1));
    container.listen(other, (_, _) {});
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(page(['1'], 'a'));
    await tick();
    final item = container.read(provider).loading.data.last;
    final source = container.read(provider).source;
    var pin = notifier.setPinned(item, source, false);
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({'code': 0});
    await pin;
    final otherNotifier = container.read(other.notifier);
    var more = otherNotifier.onLoadMore();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(page(['3'], 'b'));
    await more;
    expect(container.read(other).loading.data.map((item) => item.idStr), [
      '3',
      '1',
    ]);
    expect(container.read(other).loading.data.first.isPinned, isTrue);
    pin = notifier.setPinned(item, source, true);
    await interceptor.waitForRequests(5);
    requests[4].reply.complete({'code': 0});
    await pin;
    more = otherNotifier.onLoadMore();
    await interceptor.waitForRequests(6);
    Map<String, dynamic> staleTop() => {
      'code': 0,
      'data': {
        'has_more': false,
        'items': [
          {
            'id_str': '2',
            'modules': {
              'module_tag': {'text': '置顶'},
            },
          },
        ],
      },
    };
    requests[5].reply.complete(staleTop());
    await more;
    expect(
      container.read(other).loading.data.any((item) => item.isPinned),
      isFalse,
    );
    final refresh = otherNotifier.onRefresh();
    await interceptor.waitForRequests(7);
    requests[6].reply.complete(staleTop());
    await refresh;
    expect(container.read(other).loading.data.single.isPinned, isTrue);
  });

  test('页面释放后写入锁保留到请求完成，已确认删除仍通知存活空间', () async {
    final notifier = await start();
    final source = container.read(provider).source;
    final item = container.read(provider).loading.data.first;
    final actions = container.read(dynamicsActionsProvider);
    final pending = notifier.removeItem(item, source);
    await interceptor.waitForRequests(2);
    container.invalidate(provider);
    await container.pump();
    await interceptor.waitForRequests(3);
    expect(await actions.remove(original, '1'), isA<Error>());
    requests[1].reply.complete({'code': 0});
    expect((await pending).isSuccess, isTrue);
    requests[2].reply.complete(page(['1', '4'], '', more: false));
    await tick();
    expect(container.read(provider).loading.data.single.idStr, '4');
  });

  test('他人空间不能写入，同 UID 换凭据后旧操作不污染新快照', () async {
    final notifier = await start();
    final source = container.read(provider).source;
    final item = container.read(provider).loading.data.first;
    final pending = notifier.removeItem(item, source);
    await interceptor.waitForRequests(2);
    Accounts.replaceCredentials(account('new'));
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(page(['1'], '', more: false));
    await tick();
    requests[1].reply.complete({'code': 0});
    expect((await pending).isSuccess, isTrue);
    expect(container.read(provider).loading.data.single.idStr, '1');
    final other = memberDynamicsProvider((owner: Object(), mid: 2));
    container.listen(other, (_, _) {});
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(page(['2'], '', more: false));
    await tick();
    final otherState = container.read(other);
    expect(
      await container
          .read(other.notifier)
          .removeItem(otherState.loading.data.first, otherState.source),
      isA<Error>(),
    );
    expect(requests, hasLength(4));
  });
  Map<String, dynamic> visiblePage({bool pinned = false}) => {
    'code': 0,
    'data': {
      'has_more': false,
      'offset': '',
      'items': [
        {
          'id_str': '1',
          'type': 'DYNAMIC_TYPE_WORD',
          'modules': {
            'module_author': {'mid': 1, 'name': '空间作者'},
            if (pinned) 'module_tag': {'text': '置顶'},
            'module_stat': {
              'forward': {'count': 0},
              'comment': {'count': 0},
              'like': {'count': 0, 'status': false},
            },
          },
        },
      ],
    },
  };
  Future<void> until(WidgetTester tester, int count) async {
    for (var i = 0; i < 200 && requests.length < count; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(requests, hasLength(count));
  }

  Future<void> mount(WidgetTester tester, {bool pinned = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const Scaffold(body: MemberDynamicsPage(mid: 1)),
        ),
      ),
    );
    await until(tester, 1);
    requests[0].reply.complete(visiblePage(pinned: pinned));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    final dismissal = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissal;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    Get.reset();
  }

  testWidgets('实际空间删除确认绑定原查询，刷新后旧弹窗不写入，新确认删除并提示', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除'));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除该动态?'), findsOneWidget);
    updates.published(original);
    await until(tester, 2);
    requests[1].reply.complete(visiblePage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(find.text('空间作者'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除'));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await until(tester, 3);
    expect(requests.last.options.path, Api.removeDynamic);
    requests.last.reply.complete({'code': 0});
    await tester.pumpAndSettle();
    expect(find.text('空间作者'), findsNothing);
    expect(find.text('删除成功'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('实际空间菜单将标签置顶识别为取消置顶，并保留操作提示', (tester) async {
    await mount(tester, pinned: true);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('取消置顶'));
    await until(tester, 2);
    expect(requests.last.options.path, Api.rmTopDyn);
    requests.last.reply.complete({'code': 0});
    await tester.pumpAndSettle();
    expect(find.text('取消置顶成功'), findsOneWidget);
    expect(find.text('置顶'), findsNothing);
    await finish(tester);
  });
}
