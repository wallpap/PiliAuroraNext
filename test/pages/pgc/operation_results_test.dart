import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/pgc_reviews.dart';
import 'package:pili_aurora_next/features/community/domain/pgc_review.dart';
import 'package:pili_aurora_next/features/content_discovery/application/pgc_feed.dart';
import 'package:pili_aurora_next/pages/pgc_review/child/view.dart';
import 'package:pili_aurora_next/pages/pgc_review/post/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account(int id) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': 'fixture-$id'}),
    null,
    null,
  );
  late Account original;

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
    original = account(1);
    Accounts.accountMode[AccountType.main.index] = original;
    requests.clear();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  Map<String, dynamic> timeline(List<int> days) => {
    'code': 0,
    'result': [
      for (final day in days)
        {'date_ts': day, 'date': 'day-$day', 'day_of_week': 1, 'episodes': []},
    ],
  };
  Map<String, dynamic> reviews(List<int> ids, String next, {int? liked}) => {
    'code': 0,
    'data': {
      'list': [
        for (final id in ids)
          {
            'review_id': id,
            if (id == liked) 'stat': {'liked': 1},
          },
      ],
      'next': next,
      'count': 10,
    },
  };
  final reviewProvider = pgcReviewsProvider((
    owner: Object(),
    type: .short,
    mediaId: 1,
  ));

  ProviderContainer openReviews() =>
      ProviderContainer.test()..listen(reviewProvider, (_, _) {});

  test('时间表失败可重试，部分成功保留提示，按日期合并不依赖两侧长度', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = pgcTimelineProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    var pending = Future<void>.value();
    await interceptor.waitForRequests(2);
    for (final request in requests) {
      request.reply.complete({'code': -403, 'message': '拒绝请求'});
    }
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).loading, isA<Error>());
    pending = controller.onRefresh();
    await interceptor.waitForRequests(4);
    requests[2].reply.complete(timeline([2]));
    requests[3].reply.complete({'code': -403});
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).loading.data.single.dateTs, 2);
    expect(container.read(provider).metadata, isNotNull);
    pending = controller.onRefresh();
    await interceptor.waitForRequests(6);
    requests[4].reply.complete(timeline([2, 3]));
    requests[5].reply.complete(timeline([1, 2, 3]));
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).loading.data.map((day) => day.dateTs), [
      1,
      2,
      3,
    ]);
    expect(container.read(provider).metadata, isNull);
    expect(
      requests.every((r) => identical(r.options.extra['account'], original)),
      isTrue,
    );
  });

  test('时间表刷新乱序和关闭后的迟到结果不能覆盖当前快照', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = pgcTimelineProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    final old = Future<void>.value();
    await interceptor.waitForRequests(2);
    final latest = controller.onRefresh();
    await interceptor.waitForRequests(4);
    requests[2].reply.complete(timeline([2]));
    requests[3].reply.complete(timeline([]));
    await latest;
    requests[0].reply.complete(timeline([1]));
    requests[1].reply.complete(timeline([]));
    await old;
    expect(container.read(provider).loading.data.single.dateTs, 2);
    final closing = controller.onRefresh();
    await interceptor.waitForRequests(6);
    container.dispose();
    requests[4].reply.complete(timeline([3]));
    requests[5].reply.complete(timeline([]));
    await closing;
  });

  test('短评查询绑定账号，重复游标停止且不追加重复点评', () async {
    final container = openReviews();
    final controller = container.read(reviewProvider.notifier);
    await interceptor.waitForRequests(1);
    final replacement = account(1);
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(reviews([2], 'next'));
    await Future<void>.delayed(Duration.zero);
    final more = controller.more();
    await interceptor.waitForRequests(3);
    expect(requests.last.options.extra['account'], same(replacement));
    expect(requests.last.options.queryParameters['cursor'], 'next');
    requests.last.reply.complete(reviews([2, 3], 'next'));
    await more;
    requests[0].reply.complete(reviews([1], 'old'));
    await Future<void>.delayed(Duration.zero);
    final snapshot = container.read(reviewProvider);
    expect(snapshot.loading.data.map((item) => item.reviewId), [
      2,
      3,
    ]);
    expect(snapshot.canLoadMore, isFalse);
  });

  test('赞踩共用单项写入锁，未知计数保留，旧列表结果不回写', () async {
    final container = openReviews();
    final controller = container.read(reviewProvider.notifier);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(reviews([2], '', liked: 2));
    await Future<void>.delayed(Duration.zero);
    final before = container.read(reviewProvider);
    final item = before.loading.data.single;
    final dislike = controller.act(before, item, .dislike);
    await interceptor.waitForRequests(2);
    expect(await controller.act(before, item, .like), isNull);
    expect(requests, hasLength(2));
    expect(item.stat.disliked, isFalse);
    requests[1].reply.complete({'code': 0});
    await dislike;
    final after = container.read(reviewProvider);
    final changed = after.loading.data.single;
    expect(changed.stat, (liked: false, disliked: true, likes: null));
    final like = controller.act(after, changed, .like);
    await interceptor.waitForRequests(3);
    final refresh = controller.refresh();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(reviews([3], ''));
    await refresh;
    requests[2].reply.complete({'code': 0});
    expect(await like, isNull);
    expect(container.read(reviewProvider).loading.data.single.reviewId, 3);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const Scaffold(body: Text('原页面')),
        ),
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

  testWidgets('点评缺少可选作者、内容和统计时仍可展示', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GetMaterialApp(
            home: Scaffold(
              body: PgcReviewChildPage(
                type: PgcReviewType.short,
                name: '作品',
                mediaId: 1,
              ),
            ),
          ),
        ),
      );
      await interceptor.waitForRequests(1);
      requests.single.reply.complete({
        'code': 0,
        'data': {
          'list': [<String, dynamic>{}],
        },
      });
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('匿名用户'), findsOneWidget);
    expect(find.text('赞'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('删除失败保留点评及数量，确认删除后同步移除并阻止续页重新引入', () async {
    final container = openReviews();
    final controller = container.read(reviewProvider.notifier);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(reviews([2], 'next'));
    await Future<void>.delayed(Duration.zero);
    final before = container.read(reviewProvider);
    final item = before.loading.data.single;
    final failing = controller.act(before, item, .delete);
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -403, 'message': '拒绝删除'});
    expect(await failing, isA<Error>());
    expect(container.read(reviewProvider).loading.data, [item]);
    expect(container.read(reviewProvider).count, 10);

    final deleting = controller.act(before, item, .delete);
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({'code': 0});
    expect(await deleting, isA<Success<void>>());
    expect(container.read(reviewProvider).loading.data, isEmpty);
    expect(container.read(reviewProvider).count, 9);
    final more = controller.more();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(reviews([2, 3], ''));
    await more;
    expect(container.read(reviewProvider).loading.data.single.reviewId, 3);
  });

  Future<void> openPost(WidgetTester tester) async {
    showModalBottomSheet<void>(
      context: tester.element(find.text('原页面')),
      isScrollControlled: true,
      builder: (_) => const PgcReviewPostPanel(
        name: '作品',
        mediaId: 1,
        reviewId: 2,
        score: 4,
        content: '原草稿',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('点评提交固定草稿并禁用重复提交，成功保留后来编辑的草稿', (tester) async {
    await mount(tester);
    await openPost(tester);
    await tester.runAsync(() async {
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
      await interceptor.waitForRequests(1);
    });
    await tester.pump();
    expect(find.text('提交中…'), findsOneWidget);
    expect((requests.single.options.data as Map)['content'], '原草稿');
    expect(requests.single.options.extra['account'], same(original));
    await tester.enterText(find.byType(TextField), '新草稿');
    requests.single.reply.complete({'code': 0});
    await tester.pumpAndSettle();
    expect(find.byType(PgcReviewPostPanel), findsOneWidget);
    expect(find.text('新草稿'), findsOneWidget);
    expect(requests, hasLength(1));
    Navigator.of(tester.element(find.byType(PgcReviewPostPanel))).pop();
    await finish(tester);
  });

  testWidgets('关闭点评面板后的迟到成功不关闭后来打开的页面', (tester) async {
    await mount(tester);
    await openPost(tester);
    await tester.runAsync(() async {
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
      await interceptor.waitForRequests(1);
    });
    Navigator.of(tester.element(find.byType(PgcReviewPostPanel))).pop();
    await tester.pumpAndSettle();
    Get.to(() => const Scaffold(body: Text('新页面')));
    await tester.pumpAndSettle();
    requests.single.reply.complete({'code': 0});
    await tester.pumpAndSettle();
    expect(find.text('新页面'), findsOneWidget);
    expect(requests.single.options.path, Api.pgcReviewMod);
    await finish(tester);
  });
}
