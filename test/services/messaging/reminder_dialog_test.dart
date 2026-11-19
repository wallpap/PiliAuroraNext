import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/whisper_settings/widgets/reminder_dialog.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  testWidgets('换凭据后的旧提醒弹窗不写入，新弹窗保留原设置键和选项编码', (tester) async {
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
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MessageReminderButton(
              type: .mentions,
              title: '@我的提醒',
              icon: Icon(Icons.settings),
            ),
          ),
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

    Object settings(String title) => GrpcReq.compressProtobuf(
      GetImSettingsReply(
        pageTitle: title,
        settings: [
          MapEntry(
            12,
            Setting(
              select: SettingSelect(
                item: [
                  SelectItem(itemType: 13, text: '接收提醒', selected: true),
                  SelectItem(itemType: 27, text: '不提醒'),
                ],
              ),
            ),
          ),
        ],
      ).writeToBuffer(),
    );

    await tester.tap(find.byTooltip('@我的提醒'));
    await waitFor(1);
    final read = GetImSettingsReq.fromBuffer(
      GrpcReq.decompressProtobuf(requests.first.options.data),
    );
    expect(read.type, IMSettingType.SETTING_TYPE_OLD_AT_ME);
    requests.first.reply.complete(settings('旧账号设置'));
    await tester.pumpAndSettle();
    expect(find.text('旧账号设置'), findsOneWidget);

    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await waitFor(2);
    requests[1].reply.complete(settings('新账号设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不提醒'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));

    await tester.tap(find.byTooltip('@我的提醒'));
    await waitFor(3);
    requests[2].reply.complete(settings('新账号设置'));
    await tester.pumpAndSettle();
    expect(find.text('新账号设置'), findsOneWidget);
    await tester.tap(find.text('不提醒'));
    await waitFor(4);
    final write = SetImSettingsReq.fromBuffer(
      GrpcReq.decompressProtobuf(requests.last.options.data),
    );
    expect(requests.last.options.extra['account'], same(replacement));
    expect(write.settings.keys, [12]);
    expect(
      write.settings[12]!.select.item.map(
        (option) => (option.itemType, option.selected),
      ),
      [(13, false), (27, true)],
    );
    requests.last.reply.complete(
      GrpcReq.compressProtobuf(SetImSettingsReply().writeToBuffer()),
    );
    await tester.pumpAndSettle();
  });
}
