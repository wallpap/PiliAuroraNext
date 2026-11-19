import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/models/common/theme/theme_color_type.dart';
import 'package:pili_aurora_next/models/common/theme/theme_type.dart';
import 'package:pili_aurora_next/pages/setting/models/system_settings.dart';
import 'package:pili_aurora_next/pages/setting/models/model.dart';
import 'package:pili_aurora_next/pages/setting/pages/color_select.dart';
import 'package:pili_aurora_next/pages/setting/widgets/popup_item.dart';
import 'package:pili_aurora_next/pages/setting/widgets/setting_save.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

class _Settings extends MemoryBox<dynamic> {
  bool fail = false;
  final writes = <Map<dynamic, dynamic>>[];
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('private-storage');
    await super.put(key, value);
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> values) async {
    writes.add(Map.of(values));
    if (fail) throw StateError('private-storage');
    await super.putAll(values);
  }
}

void main() {
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  setUp(() {
    settings.data.clear();
    settings.writes.clear();
    settings.fail = false;
  });
  tearDown(Get.reset);
  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: child),
      ),
    );
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
  }

  Future<void> finish(WidgetTester tester) async {
    final dismissed = SmartDialog.dismiss(status: .allToast);
    await tester.pumpAndSettle();
    await dismissed;
    await tester.pumpWidget(const SizedBox());
  }

  Iterable<SettingsModel> flatten(Iterable<SettingsModel> items) sync* {
    for (final item in items) {
      yield item;
      if (item is SettingsGroup) yield* flatten(item.children);
    }
  }

  testWidgets('代理保存失败保留输入，成功用一次putAll保存Host和Port', (tester) async {
    final model = flatten(systemSettings).whereType<SplitModel>().first;
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => model.switchModel.onTap!(context),
          child: const Text('打开'),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'localhost');
    await tester.enterText(find.byType(TextFormField).at(1), '8080');
    settings.fail = true;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('localhost'), findsOneWidget);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    expect(find.textContaining('private-storage'), findsNothing);
    settings.fail = false;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.writes.last, {
      SettingBoxKey.systemProxyHost: 'localhost',
      SettingBoxKey.systemProxyPort: '8080',
    });
    await finish(tester);
  });

  testWidgets('主题页兼容旧配色值，保存成功后才更新所选模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(350, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await settings.putAll({
      SettingBoxKey.themeMode: 99,
      SettingBoxKey.customColor: colorThemeTypes.length,
      SettingBoxKey.dynamicColor: false,
    });
    await mount(tester, const ColorSelectPage());
    expect(find.text('当前模式：跟随系统'), findsOneWidget);
    expect(tester.takeException(), isNull);

    Future<void> pickDark() async {
      await tester.tap(find.text('主题模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
    }

    settings.fail = true;
    await pickDark();
    expect(settings.data[SettingBoxKey.themeMode], 99);
    expect(find.text('当前模式：跟随系统'), findsOneWidget);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    settings.fail = false;
    await pickDark();
    expect(settings.data[SettingBoxKey.themeMode], ThemeType.dark.index);
    expect(find.text('当前模式：深色'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Popup回调等待Future，失败后恢复选择', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await mount(
      tester,
      PopupListTile<int>(
        title: '选择',
        value: () => (1, '一'),
        options: const [(1, '一'), (2, '二')],
        onSelected: (_, _) {
          calls++;
          return gate.future;
        },
      ),
    );
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('二'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    gate.completeError(StateError('private-popup'));
    await tester.pumpAndSettle();
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('保存后应用失败保留保存值并给出独立提示', (tester) async {
    await mount(tester, const SizedBox());
    var written = false;
    final result = await saveSetting(
      key: 'apply-test',
      write: () async {
        written = true;
      },
      apply: () => throw StateError('private-apply'),
      canPresent: () => true,
    );
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(written, isTrue);
    expect(find.text('设置已保存，应用失败，请重启后重试'), findsOneWidget);
    await finish(tester);
  });
}
