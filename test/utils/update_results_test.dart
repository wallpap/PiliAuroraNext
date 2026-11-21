import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/services/update/app_release.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/update/update.dart';

import '../support/memory_box.dart';

class _Settings extends MemoryBox<dynamic> {
  Completer<void>? pending;
  int saves = 0;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    saves++;
    await pending?.future;
    await super.put(key, value);
  }
}

void main() {
  final settings = _Settings();
  final release = AppRelease.latestStable([
    {'tag_name': 'v99.0.0', 'body': '更新说明'},
  ])!;
  setUpAll(() => GStorage.setting = settings);
  setUp(() async {
    settings
      ..pending = null
      ..saves = 0;
    await settings.clear();
  });
  tearDown(Get.reset);

  Future<void> mount(WidgetTester tester, {AppRelease? update}) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: const Scaffold(),
      ),
    );
    Update.showUpdate(update ?? release, isAuto: true);
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester) async {
    final closing = SmartDialog.dismiss(status: SmartStatus.allDialog);
    final toast = SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pumpAndSettle();
    await closing;
    await toast;
    await tester.pumpWidget(const SizedBox());
  }

  AppRelease withNotes(String notes) => AppRelease.latestStable([
    {'tag_name': release.tag, 'body': notes},
  ])!;

  testWidgets('以富文本显示更新说明，不解释原始 HTML 或加载远程图片', (tester) async {
    await mount(
      tester,
      update: withNotes('''
## 更新内容

- **离线下载**：改进任务列表。
- 使用 `便携版`。

[完整说明](https://example.com/release) 与 [不安全链接](file:///update.exe)。
![版本截图](https://example.com/release.png)

<style>body{display:none}</style>
'''),
    );
    final document = tester.widget<Html>(find.byType(Html)).documentElement!;
    expect(document.querySelector('h2')?.text, '更新内容');
    expect(document.querySelector('ul li strong')?.text, '离线下载');
    expect(document.querySelector('code')?.text, '便携版');
    expect(
      document.querySelectorAll('a').single.attributes['href'],
      'https://example.com/release',
    );
    expect(document.querySelectorAll('img, style'), isEmpty);
    for (final text in ['更新内容', '离线下载', '完整说明', '不安全链接', '版本截图']) {
      expect(find.textContaining(text, findRichText: true), findsWidgets);
    }
    expect(find.textContaining('## 更新内容', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('空白更新说明显示占位文案', (tester) async {
    await mount(tester, update: withNotes(' \n '));
    expect(find.text('本次发布未提供更新说明。'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('窄窗口的长说明可滚动，操作按钮始终可见', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await mount(
      tester,
      update: withNotes(
        List.generate(20, (index) => '- **更新 ${index + 1}**：优化功能。').join('\n'),
      ),
    );
    final scroll = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    for (final label in [
      '稍后',
      '此版本不再提醒',
      if (Platform.isWindows) ...['便携版 ZIP', '安装版 EXE'] else '下载更新',
    ]) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('忽略版本等待保存回执，重复点击只保存一次，成功后关闭', (tester) async {
    settings.pending = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('此版本不再提醒'));
    await tester.pump();
    await tester.tap(find.text('此版本不再提醒'));
    await tester.pump();
    expect(settings.saves, 1);
    expect(find.text('发现新版本 v99.0.0'), findsOneWidget);
    expect(settings.get(SettingBoxKey.updateIgnoredVersion), isNull);
    settings.pending!.complete();
    await tester.pumpAndSettle();
    expect(settings.get(SettingBoxKey.updateIgnoredVersion), release.tag);
    expect(find.text('发现新版本 v99.0.0'), findsNothing);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('忽略版本保存失败保留弹窗，提示安全文案并允许重试', (tester) async {
    settings.pending = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('此版本不再提醒'));
    await tester.pump();
    settings.pending!.completeError(StateError('private-value'));
    await tester.pumpAndSettle();
    expect(find.text('设置未保存，请重试'), findsOneWidget);
    expect(find.textContaining('private-value'), findsNothing);
    expect(find.text('发现新版本 v99.0.0'), findsOneWidget);
    expect(settings.get(SettingBoxKey.updateIgnoredVersion), isNull);
    settings.pending = null;
    await tester.tap(find.text('此版本不再提醒'));
    await tester.pumpAndSettle();
    expect(settings.saves, 2);
    expect(settings.get(SettingBoxKey.updateIgnoredVersion), release.tag);
    expect(find.text('发现新版本 v99.0.0'), findsNothing);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  for (final failed in [false, true]) {
    testWidgets('弹窗关闭后的迟到${failed ? '失败不提示' : '成功不关闭新弹窗'}', (tester) async {
      settings.pending = Completer<void>();
      await mount(tester);
      await tester.tap(find.text('此版本不再提醒'));
      await tester.pump();
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      Update.showUpdate(release, isAuto: true);
      await tester.pumpAndSettle();
      if (failed) {
        settings.pending!.completeError(StateError('private-value'));
      } else {
        settings.pending!.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v99.0.0'), findsOneWidget);
      expect(find.text('设置未保存，请重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    });
  }
}
