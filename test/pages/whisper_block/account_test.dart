import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/pages/whisper_block/view.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  testWidgets('换凭据后的旧确认不删除屏蔽词，新确认更新当前账号', (tester) async {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    final interceptor = ControlledInterceptor(
      headers: Headers.fromMap({
        'grpc-status': ['0'],
      }),
    );
    final requests = interceptor.requests;
    addTearDown(() async {
      for (final request in requests) {
        if (!request.reply.isCompleted) request.reply.complete(<int>[]);
      }
      Request.dio.close(force: true);
      await interceptor.close();
    });
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
    LoginAccount account(String csrf) => LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
      null,
      null,
    )..activated = true;
    Accounts.accountMode[AccountType.main.index] = account('old');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const WhisperBlockPage(),
        ),
      ),
    );

    Future<void> waitFor(int count) async {
      for (
        var attempt = 0;
        attempt < 100 && requests.length < count;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(requests, hasLength(count));
    }

    final words = GrpcReq.compressProtobuf(
      KeywordBlockingListReply(
        items: [KeywordBlockingItem(keyword: '保留词')],
        listLimit: 10,
        charLimit: 20,
      ).writeToBuffer(),
    );
    await waitFor(1);
    requests.last.reply.complete(words);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留词'));
    await tester.pumpAndSettle();
    expect(find.text('删除屏蔽词？'), findsOneWidget);

    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await waitFor(2);
    requests.last.reply.complete(words);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(find.text('保留词'), findsOneWidget);

    await tester.tap(find.text('保留词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await waitFor(3);
    final request = requests.last.options;
    expect(request.extra['account'], same(replacement));
    expect(
      KeywordBlockingDeleteReq.fromBuffer(
        GrpcReq.decompressProtobuf(request.data),
      ).keyword,
      '保留词',
    );
    expect(find.text('保留词'), findsOneWidget);
    requests.last.reply.complete(
      GrpcReq.compressProtobuf(KeywordBlockingDeleteReply().writeToBuffer()),
    );
    await tester.pumpAndSettle();
    expect(find.text('还未添加屏蔽词'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
