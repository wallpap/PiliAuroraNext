import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/pages/member_dynamics/controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Member extends MemberDynamicsController {
  _Member() : super(1);
  final queries = <Future<void>>[];
  @override
  Future<void> queryData([bool isRefresh = true]) {
    final query = super.queryData(isRefresh);
    queries.add(query);
    return query;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account(int id, [String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  late LoginAccount original;
  late LoginAccount recommend;
  final controllers = <GetxController>[];

  T own<T extends GetxController>(T controller) {
    controllers.add(controller);
    return controller;
  }

  DynamicItemModel item(String id) => DynamicItemModel.fromJson({'id_str': id});
  Map<String, dynamic> dynamics(String id) => {
    'code': 0,
    'data': {
      'has_more': false,
      'offset': id,
      'items': [
        {'id_str': id},
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
  });
  setUp(() async {
    original = account(1);
    recommend = account(2);
    Accounts.accountMode[AccountType.main.index] = original;
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    await GStorage.localCache.putAll({
      LocalCacheKey.mixinKey: 'synthetic',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    Get.parameters = {'id': '12', 'name': '话题'};
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

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final deadline = tester.binding.clock.now().add(const Duration(seconds: 3));
    while (!condition() && tester.binding.clock.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
    Get.parameters = {'id': '12', 'name': '话题'};
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('空间删除防重复，待确认及列表或账号变化不误删', (tester) async {
    await mount(tester);
    final controller = own(MemberDynamicsController(1));
    final list = [item('1')];
    controller.loadingState.value = Success(list);
    var remove = controller.onRemove('1');
    await controller.onRemove('1');
    await until(tester, () => requests.length == 1);
    expect(requests.single.options.path, Api.removeDynamic);
    expect(requests.single.options.extra['account'], same(original));
    requests.single.reply.complete({'code': '0'});
    await settle(tester);
    await remove;
    expect(list, hasLength(1));
    expect(find.text('操作结果待确认，请先核对后再操作'), findsOneWidget);

    remove = controller.onRemove('1');
    await until(tester, () => requests.length == 2);
    final refreshed = [item('1')];
    controller.loadingState.value = Success(refreshed);
    requests.last.reply.complete({'code': 0});
    await settle(tester);
    await remove;
    expect(refreshed, hasLength(1));
    expect(list, hasLength(1));
    expect(find.text('删除成功'), findsNothing);

    remove = controller.onRemove('1');
    await until(tester, () => requests.length == 3);
    Accounts.accountMode[AccountType.main.index] = account(3);
    requests.last.reply.complete({'code': 0});
    await settle(tester);
    await remove;
    expect(refreshed, hasLength(1));
    await finish(tester);
  });

  testWidgets('空间置顶互斥，保留普通标签并只取消目标置顶', (tester) async {
    await mount(tester);
    final controller = own(MemberDynamicsController(1));
    final ordinary = item('1')..modules.moduleTag = ModuleTag(text: '普通标签');
    final oldTop = item('2')..modules.moduleTag = ModuleTag(text: '置顶');
    final target = item('3');
    final list = [ordinary, oldTop, target];
    controller.loadingState.value = Success(list);
    var setTop = controller.onSetTop(false, '3');
    await controller.onSetTop(false, '3');
    await controller.onRemove('1');
    await until(tester, () => requests.length == 1);
    expect(requests.single.options.extra['account'], same(original));
    requests.single.reply.complete({'code': 0});
    await settle(tester);
    await setTop;
    expect(list, [target, ordinary, oldTop]);
    expect(ordinary.modules.moduleTag?.text, '普通标签');
    expect(oldTop.modules.moduleTag, isNull);
    expect(target.modules.moduleTag?.text, '置顶');

    list
      ..remove(target)
      ..add(target);
    setTop = controller.onSetTop(true, '3');
    await until(tester, () => requests.length == 2);
    requests.last.reply.complete({'code': -667777, 'message': '拒绝置顶'});
    await settle(tester);
    await setTop;
    expect(target.modules.moduleTag?.text, '置顶');
    expect(find.text('拒绝置顶'), findsOneWidget);
    setTop = controller.onSetTop(true, '3');
    await until(tester, () => requests.length == 3);
    requests.last.reply.complete({'code': 0});
    await settle(tester);
    await setTop;
    expect(target.modules.moduleTag, isNull);
    expect(ordinary.modules.moduleTag?.text, '普通标签');
    expect(list, [ordinary, oldTop, target]);
    await finish(tester);
  });

  test('空间动态凭据替换后重载，旧查询不覆盖新列表并释放订阅', () async {
    final controller = own(_Member())..onInit();
    await interceptor.waitForRequests(1);
    final replacement = account(1, 'replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests.last.reply.complete(dynamics('2'));
    await controller.queries.last;
    requests.first.reply.complete(dynamics('1'));
    await controller.queries.first;
    expect(controller.loadingState.value.data!.single.idStr, '2');
    expect(controller.offset, '2');
    controller.onDelete();
    Accounts.replaceCredentials(account(1, 'closed'));
    expect(requests, hasLength(2));
  });

  test('空间动态分页拒绝重复游标、去重并保留失败页重试位置', () async {
    final controller = own(MemberDynamicsController(1));
    Map<String, dynamic> page(List<String> ids, String cursor) => {
      'code': 0,
      'data': {
        'has_more': true,
        'offset': cursor,
        'items': [
          for (final id in ids) {'id_str': id},
        ],
      },
    };
    var pending = controller.queryData();
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(page(['1', '2'], 'a'));
    await pending;
    pending = controller.onLoadMore();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -403, 'message': '分页失败'});
    await pending;
    expect(controller.loadMoreError.value?.errMsg, '分页失败');
    expect(controller.offset, 'a');
    expect(controller.page, 2);
    await controller.onLoadMore();
    expect(requests, hasLength(2));
    pending = controller.retryLoadMore();
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(page(['2', '3', '3'], 'b'));
    await pending;
    expect(controller.loadMoreError.value, isNull);
    expect(controller.loadingState.value.data!.map((item) => item.idStr), [
      '1',
      '2',
      '3',
    ]);
    pending = controller.onLoadMore();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(page(['4'], 'a'));
    await pending;
    expect(controller.isEnd, isTrue);
    await controller.onLoadMore();
    expect(requests, hasLength(4));
  });

  test('空间动态连续无增长页即使游标变化也有限界', () async {
    final controller = own(MemberDynamicsController(1));
    controller.loadingState.value = Success([item('1')]);
    controller.page = 2;
    for (var index = 0; index < 5; index++) {
      final pending = controller.onLoadMore();
      await interceptor.waitForRequests(index + 1);
      requests[index].reply.complete({
        'code': 0,
        'data': {
          'has_more': true,
          'offset': 'cursor-$index',
          'items': [
            {'id_str': '1'},
          ],
        },
      });
      await pending;
    }
    expect(controller.isEnd, isTrue);
    expect(controller.loadingState.value.data!.single.idStr, '1');
    await controller.onLoadMore();
    expect(requests, hasLength(5));
  });

  test('空间动态旧分页失败不污染刷新结果，刷新清理重试状态', () async {
    final controller = own(MemberDynamicsController(1))
      ..loadingState.value = Success([item('1')])
      ..page = 2
      ..offset = 'a';
    final old = controller.onLoadMore();
    await interceptor.waitForRequests(1);
    final refresh = controller.onRefresh();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(dynamics('2'));
    await refresh;
    requests[0].reply.complete({'code': -403, 'message': '旧分页失败'});
    await old;
    expect(controller.loadMoreError.value, isNull);
    expect(controller.loadingState.value.data!.single.idStr, '2');
  });

  testWidgets('空间动态旧确认来源不能操作刷新后的同ID动态，新账号不能写入其他空间', (tester) async {
    await mount(tester);
    final controller = own(MemberDynamicsController(1));
    final source = item('1');
    controller.loadingState.value = Success([source]);
    final remove = controller.removalAction(source);
    final top = controller.topAction(source);
    controller.loadingState.value = Success([item('1')]);
    await remove('1');
    await top(false, '1');
    Accounts.accountMode[AccountType.main.index] = account(3);
    await controller.onRemove('1');
    await controller.onSetTop(false, '1');
    expect(requests, isEmpty);
    await finish(tester);
  });

  testWidgets('空间动态删除后分页不复活已确认删除的条目，过期置顶意图不反向操作', (tester) async {
    await mount(tester);
    final controller = own(MemberDynamicsController(1));
    controller.loadingState.value = Success([item('1'), item('2')]);
    final removal = controller.onRemove('1');
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete({'code': 0});
    await settle(tester);
    await removal;
    final pending = controller.onLoadMore();
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'has_more': false,
        'offset': 'next',
        'items': [
          {'id_str': '1'},
          {'id_str': '3'},
        ],
      },
    });
    await settle(tester);
    await pending;
    expect(controller.loadingState.value.data!.map((item) => item.idStr), [
      '2',
      '3',
    ]);
    await controller.onSetTop(true, '3');
    expect(requests, hasLength(2));
    await finish(tester);
  });
}
