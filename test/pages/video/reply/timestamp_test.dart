import 'package:flutter/gestures.dart';
import 'package:pili_aurora_next/common/widgets/text_more/text_more.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_video_tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo, Content, Member;
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.video = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    await Diagnostics.instance.configure(
      level: DiagnosticLogLevel.warning,
    );
  });
  tearDownAll(Diagnostics.instance.dispose);

  testWidgets('动态评论的时间戳不查找不存在的视频控制器', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyItemGrpc(
            replyItem: commentFromProtocol(
              ReplyInfo(
                content: Content(message: '时间是 03:12'),
                member: Member(name: '测试用户'),
              ),
            ),
            replyLevel: 0,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      Diagnostics.instance.recentLogs.where(
        (record) => record['message'].toString().contains('failed to validate'),
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('视频时间戳只跳转当前来源，超范围和失效后不跳转', (tester) async {
    final seeks = <Duration>[];
    int? duration = 200000;
    final CommentVideoTools tools = (
      durationMilliseconds: () => duration,
      seek: (position) {
        seeks.add(position);
        return true;
      },
      position: () => null,
      capture: () => null,
      share: (_) => null,
    );

    Future<TextSpan> render(String message) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          home: Scaffold(
            body: ReplyItemGrpc(
              replyItem: commentFromProtocol(
                ReplyInfo(
                  content: Content(message: message),
                  member: Member(name: '测试'),
                ),
              ),
              replyLevel: 0,
              videoTools: tools,
            ),
          ),
        ),
      );
      TextSpan? found;
      for (final rich in tester.widgetList<TextMore>(find.byType(TextMore))) {
        void visit(InlineSpan span) {
          if (span is TextSpan) {
            if (span.text?.contains(message) == true) found = span;
            for (final child in span.children ?? <InlineSpan>[]) {
              visit(child);
            }
          }
        }

        if (rich.textSpan != null) visit(rich.textSpan!);
      }
      expect(found, isNotNull);
      return found!;
    }

    final valid = await render('03:12');
    expect(valid.recognizer, isA<TapGestureRecognizer>());
    (valid.recognizer! as TapGestureRecognizer).onTap!();
    expect(seeks, [const Duration(seconds: 192)]);
    final huge = await render('999999999999999999999999:00');
    expect(huge.recognizer, isNull);
    expect(tester.takeException(), isNull);
    duration = 1000;
    expect((await render('03:12')).recognizer, isNull);
    duration = null;
    expect((await render('03:12')).recognizer, isNull);
    duration = 200000;
    final beforeClose = await render('03:12');
    duration = null;
    (beforeClose.recognizer! as TapGestureRecognizer).onTap!();
    expect(seeks, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
