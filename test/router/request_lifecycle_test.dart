import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/app_scheme.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/navigation_request.dart';
import 'package:pili_aurora_next/utils/url_utils.dart';

import 'route_request_fixture.dart';

void main() {
  final fixture = RouteRequestFixture(
    redirectTo: 'https://www.bilibili.com/video/av123',
  );
  final requests = fixture.requests;
  final openedVideos = fixture.openedVideos;

  Map<String, Object> video(int cid) => {
    'code': 0,
    'data': [
      {'cid': cid},
    ],
  };
  const failed = {'code': -404, 'message': '迟到错误'};

  testWidgets('旧视频查询先失败不提示、不关闭新查询或其他任务的加载', (tester) async {
    await fixture.mount(tester);
    SmartDialog.showLoading(msg: '其他任务');
    final first = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    final latest = PiliScheme.videoPush(124, null);
    await fixture.until(tester, () => requests.length == 2);
    await fixture.complete(tester, first, 0, failed);
    expect(find.text('迟到错误'), findsNothing);
    expect(
      SmartDialog.checkExist(dialogTypes: {SmartAllDialogType.loading}),
      true,
    );
    expect(find.text('获取中...'), findsOneWidget);
    await fixture.complete(tester, latest, 1, video(42));
    expect(openedVideos, hasLength(1));
    expect(openedVideos.single['aid'], 124);
    expect(find.text('获取中...'), findsNothing);
    expect(
      SmartDialog.checkExist(dialogTypes: {SmartAllDialogType.loading}),
      true,
    );
    final loading = SmartDialog.dismiss(status: SmartStatus.loading);
    await tester.pumpAndSettle();
    await loading;
    await fixture.finish(tester);
  });

  testWidgets('新视频先完成后，旧成功回包不会再次导航', (tester) async {
    await fixture.mount(tester);
    final first = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    final latest = PiliScheme.videoPush(124, null);
    await fixture.until(tester, () => requests.length == 2);
    await fixture.complete(tester, latest, 1, video(42));
    await fixture.complete(tester, first, 0, video(43));
    expect(openedVideos, hasLength(1));
    expect(openedVideos.single['cid'], 42);
    await fixture.finish(tester);
  });

  for (final playlist in [false, true]) {
    for (final role in [AccountType.main, AccountType.heartbeat]) {
      testWidgets('${playlist ? '播放列表' : '链接视频'}切换$role后拒绝旧回包', (tester) async {
        await fixture.mount(tester);
        final account = Accounts.heartbeat;
        final Future<void> operation;
        if (playlist) {
          operation = PiliScheme.routePushFromUrl(
            'https://m.bilibili.com/playlist/pl123?bvid=BV17x411w7KC',
          ).then((_) {});
        } else {
          operation = PiliScheme.videoPush(123, null);
        }
        await fixture.until(tester, () => requests.length == 1);
        expect(requests.single.options.extra['account'], same(account));
        Accounts.accountMode[role.index] = LoginAccount(
          BiliCookieJar.fromJson({
            'DedeUserID': '2',
            'bili_jct': 'replacement',
          }),
          null,
          null,
        );
        await fixture.complete(tester, operation, 0, video(42));
        expect(openedVideos, isEmpty);
        expect(find.text('视频暂无可播放内容'), findsNothing);
        await fixture.finish(tester);
      });
    }
  }

  testWidgets('播放列表空结果明确提示，保持原页面', (tester) async {
    await fixture.mount(tester);
    final operation = PiliScheme.routePushFromUrl(
      'https://m.bilibili.com/playlist/pl123?bvid=BV17x411w7KC',
    ).then((_) {});
    await fixture.until(tester, () => requests.length == 1);
    await fixture.complete(tester, operation, 0, {'code': 0, 'data': []});
    expect(find.text('视频暂无可播放内容'), findsOneWidget);
    expect(openedVideos, isEmpty);
    await fixture.finish(tester);
  });

  testWidgets('当前视频空结果明确提示，并关闭自己的加载', (tester) async {
    await fixture.mount(tester);
    final operation = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    await fixture.complete(tester, operation, 0, {'code': 0, 'data': []});
    expect(find.text('视频暂无可播放内容'), findsOneWidget);
    expect(find.text('获取中...'), findsNothing);
    expect(openedVideos, isEmpty);
    await fixture.finish(tester);
  });

  testWidgets('离页后即使返回同一页面，旧视频查询仍然失效', (tester) async {
    await fixture.mount(tester);
    final operation = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    Get.toNamed('/other');
    await tester.pump(const Duration(milliseconds: 500));
    Get.back();
    await tester.pump(const Duration(milliseconds: 500));
    await fixture.complete(tester, operation, 0, video(42));
    expect(openedVideos, isEmpty);
    expect(find.text('来源页面'), findsOneWidget);
    expect(find.text('获取中...'), findsNothing);
    await fixture.finish(tester);
  });

  testWidgets('普通路由离页再返回后丢弃旧查询', (tester) async {
    await fixture.mount(tester);
    final navigator = Get.key.currentState!
      ..push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('普通来源'))),
      );
    await tester.pumpAndSettle();
    final operation = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    navigator.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('普通下一页'))),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await fixture.complete(tester, operation, 0, video(42));
    expect(openedVideos, isEmpty);
    expect(find.text('普通来源'), findsOneWidget);
    expect(find.text('获取中...'), findsNothing);
    await fixture.finish(tester);
  });

  testWidgets('当前普通路由的成功查询正常导航', (tester) async {
    await fixture.mount(tester);
    Get.key.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('普通来源'))),
    );
    await tester.pumpAndSettle();
    final operation = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    await fixture.complete(tester, operation, 0, video(42));
    expect(openedVideos, hasLength(1));
    expect(openedVideos.single['cid'], 42);
    await fixture.finish(tester);
  });

  testWidgets('普通路由移除后旧查询不提示失败', (tester) async {
    await fixture.mount(tester);
    final navigator = Get.key.currentState!;
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('普通来源')),
    );
    navigator.push(route);
    await tester.pumpAndSettle();
    final operation = PiliScheme.videoPush(123, null);
    await fixture.until(tester, () => requests.length == 1);
    navigator.removeRoute(route);
    await tester.pumpAndSettle();
    await fixture.complete(tester, operation, 0, failed);
    expect(find.text('迟到错误'), findsNothing);
    expect(openedVideos, isEmpty);
    await fixture.finish(tester);
  });

  testWidgets('查询自己的确认弹窗关闭后仍可消费结果', (tester) async {
    await fixture.mount(tester);
    final request = NavigationRequest();
    final confirmation = showDialog<bool>(
      context: Get.key.currentContext!,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认操作'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认操作'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
    expect(request.isCurrent, isTrue);
    await request.close();
    await fixture.finish(tester);
  });

  for (final (name, start) in <(String, Future<void> Function())>[
    ('动态', () => PageUtils.pushDynFromId(id: '1')),
    ('番剧', () => PageUtils.viewPgc(seasonId: 1)),
    ('课程', () => PageUtils.viewPugv(seasonId: 1)),
    ('匹配视频链接', () => UrlUtils.matchUrlPush('av123', '')),
    (
      '播放列表',
      () async {
        await PiliScheme.routePushFromUrl(
          'https://m.bilibili.com/playlist/pl123?bvid=BV17x411w7KC',
        );
      },
    ),
  ]) {
    testWidgets('$name离页后的错误回包不打扰新页面', (tester) async {
      await fixture.mount(tester);
      final operation = start();
      await fixture.until(tester, () => requests.length == 1);
      Get.toNamed('/other');
      await tester.pump(const Duration(milliseconds: 500));
      SmartDialog.showLoading(msg: '新页面任务');
      await fixture.complete(tester, operation, 0, failed);
      expect(find.text('迟到错误'), findsNothing);
      expect(find.text('其他页面'), findsOneWidget);
      expect(
        SmartDialog.checkExist(dialogTypes: {SmartAllDialogType.loading}),
        true,
      );
      final loading = SmartDialog.dismiss(status: SmartStatus.loading);
      await tester.pumpAndSettle();
      await loading;
      await fixture.finish(tester);
    });
  }

  testWidgets('短链接重定向迟到后不再查询视频或回退网页', (tester) async {
    await fixture.mount(tester);
    var done = false;
    var handled = false;
    final operation = PiliScheme.routePushFromUrl('https://b23.tv/short')
        .then((value) {
          handled = value;
          done = true;
        });
    await fixture.until(tester, () => requests.length == 1);
    Get.toNamed('/other');
    await tester.pump(const Duration(milliseconds: 500));
    requests.single.reply.complete('');
    await fixture.until(tester, () => done);
    await operation;
    expect(handled, true);
    expect(requests, hasLength(1));
    expect(openedVideos, isEmpty);
    expect(find.text('其他页面'), findsOneWidget);
    await fixture.finish(tester);
  });
}
