import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/result.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';
import 'package:pili_aurora_next/pages/share/view.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/controller.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/messaging/conversation.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/messaging/sharing.dart';
import 'package:pili_aurora_next/services/messaging/sharing_adapter.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/memory_box.dart';

class _VideoController extends GetxController implements VideoDetailController {
  @override
  String playedTimePos(bool hasParams) => '?t=12.0';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShareController extends PgcIntroController {
  _ShareController() {
    isPgc = true;
  }

  final _video = _VideoController();

  @override
  VideoDetailController get videoDetailCtr => _video;
}

class _UgcShareController extends UgcIntroController {
  final _video = _VideoController();
  @override
  VideoDetailController get videoDetailCtr => _video;
}

class _SharingAdapter extends SharingAdapter {
  @override
  Future<LoadingState<List<ShareRecipient>>> recentRecipients(
    Account account,
  ) async => const Success([
    ShareRecipient(id: 456, name: '合成收件人', avatar: ''),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Account previousAccount;

  setUpAll(() async {
    GStorage.setting = MemoryBox();
    GStorage.localCache = MemoryBox();
    await GStorage.localCache.put(LocalCacheKey.buvid, 'synthetic-buvid');
  });

  setUp(() {
    previousAccount = Accounts.main;
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123'}),
      null,
      null,
    );
    final session = Messaging.instance.session;
    session.resource(
      MessageSharing,
      () => MessageSharing(
        session: session,
        cache: conversationCacheFor(session),
        adapter: _SharingAdapter(),
      ),
      (_) {},
    );
  });

  tearDown(() {
    Accounts.accountMode[AccountType.main.index] = previousAccount;
    Messaging.onAccountChanged();
    Get.reset();
  });

  for (final ugc in [false, true]) {
    testWidgets('${ugc ? 'UGC' : 'PGC'} 分享菜单切号后不打开消息面板', (tester) async {
      final CommonIntroController controller = ugc
          ? (_UgcShareController()
              ..bvid = 'BV17x411w7KC'
              ..cid.value = 1)
          : (_ShareController()
              ..pgcItem = PgcInfoModel.fromJson({
                'title': '测试',
                'type': 1,
                'episodes': [
                  {'ep_id': 123},
                ],
              })
              ..epId = 123);
      await tester.pumpWidget(
        GetMaterialApp(
          navigatorObservers: [FlutterSmartDialog.observer],
          builder: FlutterSmartDialog.init(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => controller.actionShareVideo(context),
                child: const Text('打开分享'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开分享'));
      await tester.pumpAndSettle();
      Accounts.accountMode[AccountType.main.index] = const NoAccount();
      await tester.tap(find.text('分享至消息'));
      await tester.pumpAndSettle();
      expect(find.byType(SharePanel), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '${ugc ? 'UGC' : 'PGC'} 分享菜单打开海报并复制 PNG',
      (tester) async {
        MethodCall? clipboard;
        const channel = MethodChannel('piliauroranext/image_clipboard');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              ..setMockMethodCallHandler(channel, (call) async {
                clipboard = call;
                return null;
              });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final CommonIntroController controller = ugc
            ? (_UgcShareController()
                ..bvid = 'BV17x411w7KC'
                ..cid.value = 1
                ..videoDetail.value = VideoDetailData(
                  bvid: 'BV17x411w7KC',
                  title: '合成视频',
                ))
            : (_ShareController()
                ..pgcItem = PgcInfoModel.fromJson({
                  'title': '合成作品',
                  'type': 1,
                  'episodes': [
                    {'id': 123, 'title': '1', 'long_title': '原分集'},
                    {'id': 456, 'title': '2', 'long_title': '新分集'},
                  ],
                })
                ..epId = 123);
        await tester.pumpWidget(
          GetMaterialApp(
            navigatorObservers: [FlutterSmartDialog.observer],
            builder: FlutterSmartDialog.init(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => controller.actionShareVideo(context),
                  child: const Text('打开分享'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开分享'));
        await tester.pumpAndSettle();
        if (controller is _ShareController) controller.epId = 456;
        await tester.tap(find.text('生成分享卡片'));
        await tester.pumpAndSettle();
        final description = RegExp(ugc ? '合成视频' : '合成作品.*第1话.*原分集');
        expect(find.bySemanticsLabel(description), findsOneWidget);

        await tester.tap(find.text('复制图片'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (clipboard == null && DateTime.now().isBefore(deadline)) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
        expect(clipboard?.method, 'writeBitmap');
        final arguments = clipboard!.arguments as Map;
        expect(arguments['width'], 920);
        expect(arguments['height'], 1040);
        expect((arguments['png'] as Uint8List).take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(const SizedBox());
      },
      skip: !PlatformUtils.isDesktop,
    );
  }

  testWidgets('复制番剧链接包含播放进度', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String?;
            }
            return null;
          });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = _ShareController()
      ..pgcItem = PgcInfoModel.fromJson({'title': '测试', 'type': 1})
      ..epId = 123;
    await tester.pumpWidget(
      GetMaterialApp(
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => controller.actionShareVideo(context),
              child: const Text('打开分享'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开分享'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(copied, 'https://www.bilibili.com/bangumi/play/ep123?t=12.0');
    await tester.pump(const Duration(seconds: 3));
  });

  for (final fromSection in [false, true]) {
    for (final idKey in ['ep_id', 'id']) {
      testWidgets('${fromSection ? '附加内容' : '正片'}通过 $idKey 分享当前分集', (
        tester,
      ) async {
        final currentId = fromSection ? 2 : 1;
        final currentEpisode = {
          idKey: currentId,
          'show_title': '合成分集标题',
          'share_url': 'https://example.test/episodes/$currentId',
          'cover': 'https://example.test/covers/$currentId',
          if (fromSection) 'share_copy': '合成预告分享标题',
        };
        final controller = _ShareController()
          ..pgcItem = PgcInfoModel.fromJson({
            'title': '合成番剧',
            'type': 1,
            'episodes': [
              if (fromSection) {'ep_id': 1} else currentEpisode,
            ],
            'section': [
              {'title': '空分组'},
              {
                'title': '预告',
                'episodes': [
                  if (fromSection) currentEpisode else {'ep_id': 2},
                ],
              },
            ],
          })
          ..epId = currentId;
        await tester.pumpWidget(
          GetMaterialApp(
            navigatorObservers: [FlutterSmartDialog.observer],
            builder: FlutterSmartDialog.init(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => controller.actionShareVideo(context),
                  child: const Text('打开分享'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开分享'));
        await tester.pumpAndSettle();
        // 菜单打开后切换分集，分享内容仍属于菜单所展示的分集快照。
        controller.epId = 999;
        controller.pgcItem.title = '后来的标题';
        await tester.tap(find.text('分享至消息'));
        await tester.pumpAndSettle();

        final panel = tester.widget<SharePanel>(find.byType(SharePanel));
        final title = fromSection ? '合成预告分享标题' : '合成番剧 合成分集标题';
        expect(panel.content, {
          'id': '$currentId',
          'title': title,
          'url': currentEpisode['share_url'],
          'headline': title,
          'source': 16,
          'thumb': currentEpisode['cover'],
          'source_desc': '番剧',
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
