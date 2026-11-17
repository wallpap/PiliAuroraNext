import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_activity.dart';
import 'package:pili_aurora_next/grpc/bilibili/app/dynamic/v2.pb.dart'
    show
        LikeListReply,
        LikeListReq,
        ModuleAuthor,
        RepostListRsp,
        RepostListReq,
        DynamicItem,
        Extend;
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/common/dyn/like_list/view.dart';
import 'package:pili_aurora_next/pages/common/dyn/repost_list/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

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
  late ProviderContainer container;
  LoginAccount account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account();
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    for (final request in requests) {
      if (!request.reply.isCompleted) request.reply.complete(<int>[]);
    }
    await tick();
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  for (final likes in [true, false]) {
    final label = likes ? '点赞' : '转发';
    dynamic response(
      List<int> ids,
      String offset, {
      bool more = true,
      int total = 12,
    }) => GrpcReq.compressProtobuf(
      likes
          ? LikeListReply(
              totalCount: Int64(total),
              hasMore: more,
              list: [for (final id in ids) ModuleAuthor(mid: Int64(id))],
            ).writeToBuffer()
          : RepostListRsp(
              totalCount: Int64(total),
              hasMore: more,
              offset: offset,
              list: [
                for (final id in ids)
                  DynamicItem(extend: Extend(dynIdStr: '$id')),
              ],
            ).writeToBuffer(),
    );
    void expectCursor(int index, String cursor, int page) {
      final data = GrpcReq.decompressProtobuf(requests[index].options.data);
      if (likes) {
        final request = LikeListReq.fromBuffer(data);
        expect(request.dynamicId, '12');
        expect(request.uidOffset.toString(), cursor.isEmpty ? '0' : cursor);
        expect(request.page, page);
      } else {
        final request = RepostListReq.fromBuffer(data);
        expect(request.dynamicId, '12');
        expect(request.offset, cursor);
      }
    }

    test('$label 标题订阅不提前查询，首次激活互斥，失败保留名单与计数并重试原页', () async {
      final query = (owner: Object(), id: '12');
      final provider = likes
          ? dynamicLikesProvider(query)
          : dynamicRepostsProvider(query);
      container.listen(provider, (_, _) {});
      final DynamicActivity<Object> notifier = likes
          ? container.read(dynamicLikesProvider(query).notifier)
          : container.read(dynamicRepostsProvider(query).notifier);
      await tick();
      expect(requests, isEmpty);
      final first = notifier.activate();
      await notifier.activate();
      await interceptor.waitForRequests(1);
      expectCursor(0, '', 1);
      requests[0].reply.complete(response([1, 2], '2'));
      await first;
      expect(container.read(provider).metadata?.total, 12);
      final failed = notifier.onLoadMore();
      await interceptor.waitForRequests(2);
      expectCursor(1, '2', 2);
      requests[1].reply.complete(<int>[]);
      await failed;
      expect(container.read(provider).loading.data, hasLength(2));
      expect(container.read(provider).metadata?.total, 12);
      expect(container.read(provider).canLoadMore, isFalse);
      final retry = notifier.retry();
      await interceptor.waitForRequests(3);
      expectCursor(2, '2', 2);
      requests[2].reply.complete(response([2, 3], '3', total: 13));
      await retry;
      expect(container.read(provider).loading.data, hasLength(3));
      expect(container.read(provider).metadata?.total, 13);
    });

    test('$label 刷新保留快照，迟到分页不改计数，相同动态的第二页面独立查询', () async {
      final query = (owner: Object(), id: '12');
      final provider = likes
          ? dynamicLikesProvider(query)
          : dynamicRepostsProvider(query);
      container.listen(provider, (_, _) {});
      final DynamicActivity<Object> notifier = likes
          ? container.read(dynamicLikesProvider(query).notifier)
          : container.read(dynamicRepostsProvider(query).notifier);
      final first = notifier.activate();
      await interceptor.waitForRequests(1);
      requests[0].reply.complete(response([1], '1'));
      await first;
      final old = notifier.onLoadMore();
      await interceptor.waitForRequests(2);
      final refresh = notifier.onRefresh();
      await interceptor.waitForRequests(3);
      expect(container.read(provider).loading.data, hasLength(1));
      expect(container.read(provider).metadata?.total, 12);
      expectCursor(2, '', 1);
      requests[2].reply.complete(response([4], '4', more: false, total: 4));
      await refresh;
      requests[1].reply.complete(response([2], '2', total: 99));
      await old;
      expect(container.read(provider).loading.data, hasLength(1));
      expect(container.read(provider).metadata?.total, 4);
      final secondQuery = (owner: Object(), id: '12');
      final second = likes
          ? dynamicLikesProvider(secondQuery)
          : dynamicRepostsProvider(secondQuery);
      final sub = container.listen(second, (_, _) {});
      final DynamicActivity<Object> other = likes
          ? container.read(dynamicLikesProvider(secondQuery).notifier)
          : container.read(dynamicRepostsProvider(secondQuery).notifier);
      final start = other.activate();
      await interceptor.waitForRequests(4);
      requests[3].reply.complete(response([5], '5', more: false, total: 5));
      await start;
      expect(container.read(second).metadata?.total, 5);
      expect(container.read(provider).metadata?.total, 4);
      sub.close();
      await container.pump();
      Accounts.replaceCredentials(account('new'));
      expect(container.read(provider).metadata, isNull);
      expect(container.read(provider).loading, isA<Loading>());
      await interceptor.waitForRequests(5);
      requests[4].reply.complete(response([6], '6', more: false, total: 6));
      await tick();
      expect(requests, hasLength(5));
    });

    testWidgets('$label 实际面板激活与错误重试，替换资源后旧响应不回写', (tester) async {
      final owner = Object();
      Widget panel(String id) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: likes
                ? DynLikePage(query: (owner: owner, id: id), isPortrait: false)
                : DynRepostPage(
                    query: (owner: owner, id: id),
                    isPortrait: false,
                  ),
          ),
        ),
      );
      Future<void> until(int count) async {
        for (var i = 0; i < 100 && requests.length < count; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(requests, hasLength(count));
      }

      await tester.pumpWidget(panel('12'));
      await until(1);
      requests[0].reply.complete(<int>[]);
      await tester.pumpAndSettle();
      final button = find.text('点击重试');
      expect(button, findsWidgets);
      await tester.tap(button.first);
      await until(2);
      await tester.pumpWidget(panel('13'));
      await until(3);
      requests[1].reply.complete(response([], '', more: false, total: 88));
      requests[2].reply.complete(response([], '', more: false, total: 0));
      await tester.pumpAndSettle();
      final query = (owner: owner, id: '13');
      final state = likes
          ? container.read(dynamicLikesProvider(query))
          : container.read(dynamicRepostsProvider(query));
      expect(state.metadata?.total, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
