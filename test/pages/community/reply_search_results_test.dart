import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/video/reply_search_item/view.dart';
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
  LoginAccount account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;

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
    Accounts.accountMode[AccountType.main.index] = account('old');
    requests.clear();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final end = tester.binding.clock.now().add(const Duration(seconds: 3));
    while (!condition() && tester.binding.clock.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
  }

  SearchItemReq queryAt(int index) => SearchItemReq.fromBuffer(
    GrpcReq.decompressProtobuf(requests[index].options.data),
  );

  Object result(int index, String title, {bool hasNext = false}) =>
      GrpcReq.compressProtobuf(
        SearchItemReply(
          cursor: SearchItemCursorReply(hasNext: hasNext),
          items: [
            switch (queryAt(index).cursor.itemType) {
              SearchItemType.VIDEO => SearchItem(
                url: '/video/$title',
                video: VideoSearchItem(
                  type: SearchItemVideoSubType.UGC,
                  ugc: UGCVideoSearchItem(title: title, upNickname: '作者'),
                ),
              ),
              _ => SearchItem(
                url: '/article/$title',
                article: ArticleSearchItem(title: title, upNickname: '作者'),
              ),
            },
          ],
        ).writeToBuffer(),
      );

  testWidgets('附件搜索续页使用已提交词，换凭据丢弃旧结果并返回所选附件', (tester) async {
    ({String title, String url})? selection;
    await tester.pumpWidget(
      ProviderScope(
        child: ImageLoadingScope(
          enabled: false,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selection = await Navigator.of(context).push(
                      MaterialPageRoute<({String title, String url})>(
                        builder: (_) =>
                            const ReplySearchPage(oid: 42, type: 11),
                      ),
                    );
                  },
                  child: const Text('选择附件'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择附件'));
    await until(tester, () => requests.length == 2);
    for (final index in [0, 1]) {
      expect(queryAt(index).keyword, isEmpty);
      requests[index].reply.complete(result(index, '初始结果'));
    }
    await until(tester, () => find.text('初始结果').evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), '已提交');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await until(tester, () => requests.length == 4);
    await tester.enterText(find.byType(TextField), '正在编辑');
    for (final index in [2, 3]) {
      final isVideo = queryAt(index).cursor.itemType == SearchItemType.VIDEO;
      requests[index].reply.complete(result(index, '旧结果', hasNext: isVideo));
    }
    await until(tester, () => requests.length == 5);
    expect(queryAt(4).keyword, '已提交');
    expect(queryAt(4).cursor.itemType, SearchItemType.VIDEO);
    expect(queryAt(4).cursor.next.toInt(), 2);
    expect(queryAt(4).oid.toInt(), 42);
    expect(queryAt(4).type.toInt(), 11);
    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await until(tester, () => requests.length == 7);
    requests[4].reply.complete(result(4, '迟到的旧分页'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('迟到的旧分页'), findsNothing);
    expect(find.text('旧结果'), findsNothing);
    for (final index in [5, 6]) {
      final query = queryAt(index);
      expect(requests[index].options.extra['account'], same(replacement));
      expect(query.keyword, '已提交');
      expect(query.cursor.next.toInt(), 1);
      final title = query.cursor.itemType == SearchItemType.VIDEO
          ? '新视频'
          : '新专栏';
      requests[index].reply.complete(result(index, title));
    }
    await until(tester, () => find.text('新视频').evaluate().isNotEmpty);
    await tester.tap(find.text('专栏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新专栏'));
    await tester.pumpAndSettle();
    expect(selection, (title: '新专栏', url: '/article/新专栏'));
    Accounts.replaceCredentials(account('closed'));
    await tester.pump();
    expect(requests, hasLength(7));
  });
}
