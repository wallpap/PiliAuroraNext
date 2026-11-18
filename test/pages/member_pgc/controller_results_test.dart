import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/pages/member_pgc/view.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/application/space_listings.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  late SpaceListQuery query;
  SpaceBangumi controller() =>
      container.read(spaceBangumiProvider(query).notifier);
  late void Function() close;
  void start() {
    final subscription = container.listen(
      spaceBangumiProvider(query),
      (_, _) {},
    );
    close = subscription.close;
  }

  state() => container.read(spaceBangumiProvider(query));
  LoginAccount account(String token) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': token}),
    null,
    null,
  )..activated = true;
  Map<String, dynamic> data(List<int> ids, {int count = 3}) => {
    'code': 0,
    'data': {
      'count': count,
      'item': [
        for (final id in ids) {'title': '番剧$id', 'cover': '', 'param': '$id'},
      ],
    },
  };
  Future<void> resolve(int index, Object body) async {
    requests[index].reply.complete(body);
    await Future<void>.delayed(Duration.zero);
  }

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Accounts.account = MemoryBox<LoginAccount>();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
    container = ProviderContainer.test();
    query = (owner: Object(), mid: 5);
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('不依赖父页加载状态；首屏错误可重试，缺失列表不伪装为空', () async {
    start();
    await interceptor.waitForRequests(1);
    await resolve(0, {
      'code': 0,
      'data': {'count': 3},
    });
    expect(state().loading, isA<Error>());
    final reload = controller().onReload();
    await interceptor.waitForRequests(2);
    await resolve(1, data([1], count: 1));
    await reload;
    expect(state().loading.data!.single.param, '1');
    expect(!state().hasMore, isTrue);
  });

  test('分页拒绝保留内容和页码，显式重试后按新总数结束', () async {
    start();
    Future<void> pending;
    await interceptor.waitForRequests(1);
    await resolve(0, data([1]));
    pending = controller().onLoadMore();
    await controller().onLoadMore();
    await interceptor.waitForRequests(2);
    expect(requests, hasLength(2));
    await resolve(1, {'code': -403, 'message': '暂不可读取'});
    await pending;
    expect(state().error, isA<Error>());
    expect(state().loading.data!.single.param, '1');
    pending = controller().retry();
    await interceptor.waitForRequests(3);
    expect(requests.last.options.queryParameters['pn'], 2);
    await resolve(2, data([2], count: 2));
    await pending;
    expect(state().error, isNull);
    expect(!state().hasMore, isTrue);
    expect(state().loading.data!.map((row) => row.param), [
      '1',
      '2',
    ]);
  });

  test('同 UID 换凭据刷新首屏，旧分页不回写且关闭后移除订阅', () async {
    start();
    await interceptor.waitForRequests(1);
    await resolve(0, data([1]));
    final original = Accounts.main;
    final oldPage = controller().onLoadMore();
    await interceptor.waitForRequests(2);
    Accounts.replaceCredentials(account('new'));
    await interceptor.waitForRequests(3);
    expect(state().loading, isA<Loading>());
    expect(requests[1].options.extra['account'], same(original));
    expect(requests[2].options.extra['account'], same(Accounts.main));
    await resolve(2, data([3], count: 1));
    await resolve(1, {'code': -403, 'message': '旧分页错误'});
    await oldPage;
    expect(state().loading.data!.single.param, '3');
    expect(state().error, isNull);
    close();
    await container.pump();
    Accounts.replaceCredentials(account('third'));
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(3));
  });

  test('刷新替换分页后，旧失败不能覆盖新分页错误或清空新内容', () async {
    start();
    Future<void> pending;
    await interceptor.waitForRequests(1);
    await resolve(0, data([1]));
    final oldPage = controller().onLoadMore();
    await interceptor.waitForRequests(2);
    pending = controller().onRefresh();
    await interceptor.waitForRequests(3);
    await resolve(2, data([2]));
    await pending;
    await resolve(1, {'code': -403, 'message': '旧错误'});
    await oldPage;
    expect(state().error, isNull);
    expect(state().loading.data!.single.param, '2');
  });
  testWidgets('番剧页无需父控制器，目标变化与卸载释放旧查询和账号订阅', (tester) async {
    Widget view(int mid) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: MemberBangumi(mid: mid, heroTag: 'standalone'),
        ),
      ),
    );
    await tester.pumpWidget(view(5));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => interceptor.waitForRequests(1));
    await tester.pumpWidget(view(6));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => interceptor.waitForRequests(2));
    expect(requests[1].options.queryParameters['vmid'], 6);
    await tester.runAsync(() async {
      await resolve(1, data([6], count: 1));
      await resolve(0, data([5], count: 1));
    });
    await tester.pumpAndSettle();
    expect(find.text('番剧6'), findsOneWidget);
    expect(find.text('番剧5'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    Accounts.replaceCredentials(account('after-unmount'));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
