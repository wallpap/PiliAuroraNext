import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/generated/bilibili/app/dynamic/v2.pb.dart'
    show LikeListReply, ModuleAuthor, RepostListRsp, DynamicItem, Extend;
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_activity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_authors.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/author_panel.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor(
    headers: Headers.fromMap({
      'grpc-status': ['0'],
    }),
  );
  final requests = interceptor.requests;
  late LoginAccount original;
  LoginAccount account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  Map<String, dynamic> ups(
    List<int> ids, [
    String offset = 'next',
    String? liveGroup,
  ]) => {
    'code': 0,
    'data': {
      'up_list': {
        'items': ids.map((id) => {'mid': id}).toList(),
        'has_more': true,
        'offset': offset,
      },
      if (liveGroup != null) 'live_users': {'group': liveGroup, 'items': []},
    },
  };
  DynamicItemModel item({bool withSource = true}) => DynamicItemModel.fromJson({
    'id_str': '12',
    if (withSource) 'basic': {'comment_id_str': '34', 'comment_type': 11},
    'modules': {
      'module_author': {'mid': 1, 'name': '作者'},
    },
  });
  Map<String, dynamic> interaction() => {
    'code': 0,
    'data': {
      'up_reply_selection': {'status': 0, 'can_modify': true},
      'up_reply': {'status': 1, 'can_modify': true},
    },
  };

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
  setUp(() async {
    original = account();
    Accounts.accountMode[AccountType.main.index] = original;
    await GStorage.setting.put(SettingBoxKey.dynamicsShowAllFollowedUp, false);
    requests.clear();
  });
  tearDown(Get.reset);
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

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: child),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
  }

  Future<void> finish(WidgetTester tester) async {
    final dismissal = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissal;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Future<void> menu(
    WidgetTester tester,
    DynamicItemModel dynamicItem, {
    ValueChanged<int>? onSetReplySubject,
  }) async {
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => AuthorPanel(
            item: dynamicItem,
            onSetReplySubject: onSetReplySubject,
          ).morePanel(context),
          child: const Text('菜单'),
        ),
      ),
    );
    await tester.tap(find.text('菜单'));
    await settle(tester);
  }

  testWidgets('全部关注先读动态续页，再补资料，去重并保留本地已读', (tester) async {
    await GStorage.setting.put(SettingBoxKey.dynamicsShowAllFollowedUp, true);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete(ups([10], 'dynamic-2'));
    await tester.pump();
    controller.markRead(10);
    final dynamicPage = controller.onLoadMore();
    await until(tester, () => requests.length == 2);
    expect(requests[1].options.path, Api.dynUplist);
    expect(requests[1].options.queryParameters['offset'], 'dynamic-2');
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'items': [
          {'mid': 10, 'has_update': true},
          {'mid': 20, 'has_update': true},
        ],
        'has_more': false,
        'offset': '',
      },
    });
    await dynamicPage;
    expect(container.read(provider).loading.data.upList!.map((up) => up.mid), [
      20,
      10,
    ]);
    expect(
      container.read(provider).loading.data.upList!.last.hasUpdate,
      isFalse,
    );
    final followingPage = controller.onLoadMore();
    await until(tester, () => requests.length == 3);
    expect(requests[2].options.path, Api.followings);
    expect(requests[2].options.queryParameters['pn'], 1);
    requests[2].reply.complete({
      'code': 0,
      'data': {
        'list': [
          {'mid': 20, 'uname': '续页作者'},
          {'mid': 30, 'uname': '普通关注'},
        ],
      },
    });
    await followingPage;
    final list = container.read(provider).loading.data.upList!;
    expect(list.map((up) => up.mid), [20, 10, 30]);
    expect(list.first.hasUpdate, isTrue);
    expect(list.first.uname, '续页作者');
    final end = controller.onLoadMore();
    await until(tester, () => requests.length == 4);
    expect(requests[3].options.queryParameters['pn'], 2);
    requests[3].reply.complete({
      'code': 0,
      'data': {'list': []},
    });
    await end;
    expect(container.read(provider).canLoadMore, isFalse);
  });

  testWidgets('全部关注动态续页失败保留游标，刷新拒绝迟到续页', (tester) async {
    await GStorage.setting.put(SettingBoxKey.dynamicsShowAllFollowedUp, true);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete(ups([10], 'next'));
    await tester.pump();
    final failed = controller.retry();
    await until(tester, () => requests.length == 2);
    expect(requests[1].options.path, Api.dynUplist);
    requests[1].reply.complete({'code': -400, 'message': 'fixture failure'});
    await failed;
    final oldPage = controller.retry();
    await until(tester, () => requests.length == 3);
    expect(requests[2].options.queryParameters['offset'], 'next');
    final refresh = controller.onRefresh();
    await until(tester, () => requests.length == 4);
    expect(requests[3].options.path, Api.followUp);
    requests[3].reply.complete(ups([30], 'fresh'));
    await refresh;
    requests[2].reply.complete({
      'code': 0,
      'data': {
        'items': [
          {'mid': 20, 'has_update': true},
        ],
        'has_more': false,
      },
    });
    await oldPage;
    expect(container.read(provider).loading.data.upList!.single.mid, 30);
    final next = controller.onLoadMore();
    await until(tester, () => requests.length == 5);
    expect(requests[4].options.queryParameters['offset'], 'fresh');
    requests[4].reply.complete({
      'code': 0,
      'data': {
        'items': [
          {'mid': 40},
        ],
        'has_more': false,
      },
    });
    await next;
    expect(container.read(provider).loading.data.upList!.map((up) => up.mid), [
      30,
      40,
    ]);
  });

  testWidgets('动态游标停滞后转普通关注，重复页补位有界且失败页可重试', (tester) async {
    await GStorage.setting.put(SettingBoxKey.dynamicsShowAllFollowedUp, true);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete(ups([10], 'same'));
    await tester.pump();
    final more = controller.onLoadMore();
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({
      'code': 0,
      'data': (ups([10], 'same')['data'] as Map)['up_list'],
    });
    for (var page = 1; page <= 4; page++) {
      await until(tester, () => requests.length == page + 2);
      expect(requests.last.options.path, Api.followings);
      expect(requests.last.options.queryParameters['pn'], page);
      requests.last.reply.complete({
        'code': 0,
        'data': {
          'list': [
            {'mid': 10},
          ],
        },
      });
    }
    await more;
    expect(requests, hasLength(6));
    expect(container.read(provider).canLoadMore, isFalse);
    expect(container.read(provider).error, isNotNull);
    final failed = controller.retry();
    await until(tester, () => requests.length == 7);
    expect(requests.last.options.queryParameters['pn'], 5);
    requests.last.reply.complete({'code': -400, 'message': 'fixture failure'});
    await failed;
    final retry = controller.retry();
    await until(tester, () => requests.length == 8);
    expect(requests.last.options.queryParameters['pn'], 5);
    requests.last.reply.complete({
      'code': 0,
      'data': {
        'list': [
          {'mid': 20},
        ],
      },
    });
    await retry;
    expect(container.read(provider).loading.data.upList!.map((up) => up.mid), [
      10,
      20,
    ]);
  });

  testWidgets('聚合页凭据替换刷新并拒绝旧结果，释放后停止订阅', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    await until(tester, () => requests.length == 1);
    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await until(tester, () => requests.length == 2);
    expect(requests[0].options.extra['account'], same(original));
    expect(requests[1].options.extra['account'], same(replacement));
    requests[1].reply.complete(ups([2]));
    await tester.pump();
    requests[0].reply.complete(ups([1]));
    await tester.pump();
    expect(container.read(provider).loading.data.upList!.single.mid, 2);
    container.dispose();
    Accounts.replaceCredentials(account('third'));
    await tester.pump();
    expect(requests, hasLength(2));
  });

  testWidgets('作者与直播资料同批刷新，失败可重试，分页游标停滞不追加', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    void expectAuthors(List<int> ids, [String? liveGroup]) {
      final data = container.read(provider).loading.data;
      expect(data.upList?.map((up) => up.mid), ids);
      expect(data.liveUsers?.group, liveGroup);
    }

    await until(tester, () => requests.length == 1);
    requests[0].reply.complete(ups([1], 'next', '旧直播分组'));
    await tester.pump();
    var completed = false;
    final refresh = controller.onRefresh().then((_) => completed = true);
    await until(tester, () => requests.length == 2);
    await tester.pump();
    expect(completed, isFalse);
    expectAuthors([1], '旧直播分组');
    expect(container.read(provider).canLoadMore, isFalse);
    requests[1].reply.complete({'code': -403});
    await refresh;
    expect(completed, isTrue);
    expectAuthors([1], '旧直播分组');
    expect(container.read(provider).error, isNotNull);
    final retry = controller.retry();
    await until(tester, () => requests.length == 3);
    expect(requests.last.options.path, Api.followUp);
    requests.last.reply.complete(ups([2]));
    await retry;
    expectAuthors([2]);
    expect(container.read(provider).error, isNull);
    final more = controller.onLoadMore();
    await until(tester, () => requests.length == 4);
    requests.last.reply.complete({
      'code': 0,
      'data': (ups([2])['data'] as Map)['up_list'],
    });
    await more;
    expect(container.read(provider).loading.data.upList, hasLength(1));
    await controller.onLoadMore();
    expect(requests, hasLength(4));
    Accounts.replaceCredentials(account('new'));
    expect(container.read(provider).loading.dataOrNull, isNull);
    await until(tester, () => requests.length == 5);
    requests.last.reply.complete(ups([3], ''));
    await tester.pump();
    expectAuthors([3]);
  });

  testWidgets('全部关注分页持续去重，页码只在成功后推进', (tester) async {
    await GStorage.setting.put(SettingBoxKey.dynamicsShowAllFollowedUp, true);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = dynamicsAuthorsProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await until(tester, () => requests.length == 1);
    requests[0].reply.complete(ups([1], ''));
    await tester.pump();
    for (var page = 1; page <= 2; page++) {
      final more = controller.onLoadMore();
      await until(tester, () => requests.length == page + 1);
      expect(requests.last.options.queryParameters['pn'], page);
      requests.last.reply.complete({
        'code': 0,
        'data': {
          'list': [
            for (final id in [1, 2, page + 2]) {'mid': id},
          ],
        },
      });
      await more;
    }
    expect(container.read(provider).loading.data.upList!.map((e) => e.mid), [
      1,
      2,
      3,
      4,
    ]);
  });

  for (final likes in [true, false]) {
    testWidgets('${likes ? '点赞' : '转发'}列表固定账号并淘汰旧结果，重复游标终止分页', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final query = (owner: Object(), id: '12');
      final provider = likes
          ? dynamicLikesProvider(query)
          : dynamicRepostsProvider(query);
      container.listen(provider, (_, _) {});
      final DynamicActivity<Object> notifier = likes
          ? container.read(dynamicLikesProvider(query).notifier)
          : container.read(dynamicRepostsProvider(query).notifier);
      dynamic response(int id) => GrpcReq.compressProtobuf(
        likes
            ? LikeListReply(
                totalCount: Int64(5),
                hasMore: true,
                list: [ModuleAuthor(mid: Int64(id))],
              ).writeToBuffer()
            : RepostListRsp(
                totalCount: Int64(5),
                hasMore: true,
                offset: '$id',
                list: [DynamicItem(extend: Extend(dynIdStr: '$id'))],
              ).writeToBuffer(),
      );
      final old = notifier.activate();
      await until(tester, () => requests.length == 1);
      final replacement = account('new');
      Accounts.replaceCredentials(replacement);
      await until(tester, () => requests.length == 2);
      expect(requests[1].options.extra['account'], same(replacement));
      requests[1].reply.complete(response(2));
      await until(tester, () => !container.read(provider).loadingMore);
      requests[0].reply.complete(response(1));
      await old;
      final more = notifier.onLoadMore();
      await until(tester, () => requests.length == 3);
      requests[2].reply.complete(response(2));
      await more;
      final state = container.read(provider);
      if (likes) {
        expect((state.loading.data.single as ModuleAuthor).mid, Int64(2));
      } else {
        expect((state.loading.data.single as DynamicItem).extend.dynIdStr, '2');
      }
      expect(state.hasMore, isFalse);
      await notifier.onLoadMore();
      expect(requests, hasLength(3));
    });
  }

  testWidgets('互动设置缺少评论来源时不请求，切号后的旧查询不弹窗', (tester) async {
    await menu(tester, item(withSource: false), onSetReplySubject: (_) {});
    await tester.tap(find.text('互动设置'));
    await settle(tester);
    expect(requests, isEmpty);
    expect(find.text('动态缺少有效的评论来源，请刷新后重试'), findsOneWidget);
    await finish(tester);
    await menu(tester, item(), onSetReplySubject: (_) {});
    await tester.tap(find.text('互动设置'));
    await until(tester, () => requests.length == 1);
    expect(requests.single.options.extra['account'], same(original));
    Accounts.accountMode[AccountType.main.index] = account('new');
    requests.single.reply.complete(interaction());
    await settle(tester);
    expect(find.text('开启评论精选'), findsNothing);
    await finish(tester);
  });

  testWidgets('互动设置弹窗切号后不调用旧写入回调', (tester) async {
    final actions = <int>[];
    await menu(tester, item(), onSetReplySubject: actions.add);
    await tester.tap(find.text('互动设置'));
    await until(tester, () => requests.length == 1);
    requests.single.reply.complete(interaction());
    await settle(tester);
    expect(find.text('开启评论精选'), findsOneWidget);
    Accounts.accountMode[AccountType.main.index] = account('new');
    await tester.tap(find.text('开启评论精选'));
    await settle(tester);
    expect(actions, isEmpty);
    await finish(tester);
  });

  testWidgets('动态举报确认成功后才拉黑，部分失败保留举报成功', (tester) async {
    await menu(tester, item());
    await tester.tap(find.text('举报'));
    await settle(tester);
    await tester.tap(find.text('垃圾广告'));
    await tester.tap(find.textContaining('拉黑该用户'));
    await tester.tap(find.text('确定'));
    await until(tester, () => requests.length == 1);
    expect(requests[0].options.path, Api.dynamicReport);
    requests[0].reply.complete({'code': -403, 'message': '拒绝'});
    await settle(tester);
    expect(requests, hasLength(1));
    await tester.tap(find.text('确定'));
    await until(tester, () => requests.length == 2);
    requests[1].reply.complete({'code': 0});
    await until(tester, () => requests.length == 3);
    expect(requests[2].options.path, Api.relationMod);
    expect(requests[2].options.extra['account'], same(original));
    expect(requests[2].options.extra['noRetry'], isTrue);
    requests[2].reply.complete({'code': '0'});
    await settle(tester);
    expect(find.textContaining('举报成功；拉黑用户：操作结果待确认'), findsOneWidget);
    expect(find.text('请选择举报的理由：'), findsNothing);
    await finish(tester);
  });

  testWidgets('动态举报切号后的迟到成功不拉黑或提示当前账号', (tester) async {
    await menu(tester, item());
    await tester.tap(find.text('举报'));
    await settle(tester);
    await tester.tap(find.text('垃圾广告'));
    await tester.tap(find.textContaining('拉黑该用户'));
    await tester.tap(find.text('确定'));
    await until(tester, () => requests.length == 1);
    Accounts.accountMode[AccountType.main.index] = account('new');
    requests.single.reply.complete({'code': 0});
    await settle(tester);
    expect(requests, hasLength(1));
    expect(find.text('举报成功'), findsNothing);
    expect(find.text('请选择举报的理由：'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    await finish(tester);
  });
}
