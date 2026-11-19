import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:pili_aurora_next/models/common/msg/msg_unread_type.dart';
import 'package:pili_aurora_next/models/common/nav_bar_config.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/pages/main/controller.dart';
import 'package:pili_aurora_next/services/settings/badge_preferences.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = _PendingBadgeSettings();
  setUpAll(() {
    GStorage.setting = store;
    GStorage.localCache = MemoryBox<dynamic>();
    GStorage.userInfo = MemoryBox<UserInfoData>();
  });

  setUp(() async {
    Get.testMode = true;
    store.pendingMode = null;
    await GStorage.setting.clear();
    await GStorage.setting.putAll({
      SettingBoxKey.autoUpdate: false,
      SettingBoxKey.hideBottomBar: false,
    });
  });

  tearDown(() {
    Get
      ..delete<MainController>(force: true)
      ..reset();
  });

  test('导航设置损坏时保留可用标签并从第一个标签启动', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.navBarSort: [91, NavigationBarType.mine.index, 'old', 2],
      SettingBoxKey.defaultHomePage: -1,
    });
    final controller = MainController()..setNavBarConfig();
    expect(controller.navigationBars, [NavigationBarType.mine]);
    expect(controller.selectedIndex.value, 0);

    await GStorage.setting.put(SettingBoxKey.navBarSort, [91]);
    controller.setNavBarConfig();
    expect(controller.navigationBars, NavigationBarType.values);
    expect(controller.selectedIndex.value, NavigationBarType.home.index);
  });

  for (final mainTabBarView in [false, true]) {
    testWidgets('initial badge requests run after the first frame, '
        'with mainTabBarView=$mainTabBarView', (tester) async {
      await GStorage.setting.put(
        SettingBoxKey.mainTabBarView,
        mainTabBarView,
      );
      late _CountingMainController controller;
      var requestsDuringBuild = -1;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (_) {
              controller = _CountingMainController();
              Get.put<MainController>(controller);
              requestsDuringBuild =
                  controller.dynamicCalls + controller.messageCalls;
              expect(controller.navigationBars, NavigationBarType.values);
              expect(
                controller.selectedIndex.value,
                NavigationBarType.home.index,
              );
              expect(controller.hasDyn, isTrue);
              expect(controller.hasHome, isTrue);
              expect(controller.lastCheckUnreadAt, greaterThan(0));
              return const Text('首屏');
            },
          ),
        ),
      );

      expect(find.text('首屏'), findsOneWidget);
      expect(requestsDuringBuild, 0);
      expect(controller.dynamicCalls, 1);
      expect(controller.messageCalls, 1);
      expect(
        controller.phases,
        everyElement(SchedulerPhase.postFrameCallbacks),
      );
      expect(
        controller.controller,
        mainTabBarView ? isA<TabController>() : isA<PageController>(),
      );

      // 既有节流时间戳仍在初始化时设置，页面恢复不会重复触发启动请求。
      controller
        ..checkUnreadDynamic()
        ..checkUnread();
      await tester.pump();
      await tester.pump();
      expect(controller.dynamicCalls, 1);
      expect(controller.messageCalls, 1);
    });
  }

  testWidgets('closing before the first frame cancels deferred requests', (
    tester,
  ) async {
    final controller = _CountingMainController();
    Get.put<MainController>(controller);
    expect(controller.dynamicCalls, 0);
    expect(controller.messageCalls, 0);

    tester.binding.scheduleFrame();
    Get.delete<MainController>(force: true);
    expect(controller.isClosed, isTrue);
    await tester.pump();

    expect(controller.dynamicCalls, 0);
    expect(controller.messageCalls, 0);
  });

  testWidgets('角标设置落盘后才应用；隐藏期间修改消息类型不触发刷新', (tester) async {
    final controller = _CountingMainController();
    Get.put<MainController>(controller);
    await tester.pumpWidget(const SizedBox());
    expect(controller.messageCalls, 1);

    final pending = store.pendingMode = Completer<void>();
    final hide = BadgePreferences.saveMessageMode(DynamicBadgeMode.hidden);
    await tester.pump();
    expect(controller.messageBadge.value.mode, DynamicBadgeMode.number);
    pending.complete();
    await hide;
    await tester.pump();
    expect(controller.messageBadge.value.mode, DynamicBadgeMode.hidden);

    await BadgePreferences.saveMessageTypes({MsgUnReadType.reply});
    await tester.pump();
    expect(controller.messageBadge.value.types, {MsgUnReadType.reply});
    expect(controller.messageCalls, 1);
    await BadgePreferences.saveMessageMode(DynamicBadgeMode.point);
    await tester.pump();
    expect(controller.messageBadge.value.mode, DynamicBadgeMode.point);
    expect(controller.messageCalls, 2);
  });

  for (final scenario in [
    (
      'dynamic tab',
      NavigationBarType.values,
      NavigationBarType.dynamics,
      DynamicBadgeMode.number,
      DynamicBadgeMode.number,
      0,
      1,
    ),
    (
      'hidden badges',
      NavigationBarType.values,
      NavigationBarType.home,
      DynamicBadgeMode.hidden,
      DynamicBadgeMode.hidden,
      0,
      0,
    ),
    (
      'no dynamic tab',
      [NavigationBarType.home, NavigationBarType.mine],
      NavigationBarType.home,
      DynamicBadgeMode.number,
      DynamicBadgeMode.number,
      0,
      1,
    ),
    (
      'no home tab',
      [NavigationBarType.dynamics, NavigationBarType.mine],
      NavigationBarType.mine,
      DynamicBadgeMode.number,
      DynamicBadgeMode.number,
      1,
      0,
    ),
    (
      'only mine tab',
      [NavigationBarType.mine],
      NavigationBarType.home,
      DynamicBadgeMode.number,
      DynamicBadgeMode.number,
      0,
      0,
    ),
  ]) {
    final (
      name,
      tabs,
      defaultTab,
      dynamicBadge,
      messageBadge,
      expectedDynamic,
      expectedMessages,
    ) = scenario;
    testWidgets('preserves startup request conditions: $name', (tester) async {
      await GStorage.setting.putAll({
        SettingBoxKey.navBarSort: tabs.map((tab) => tab.index).toList(),
        SettingBoxKey.defaultHomePage: defaultTab.index,
        SettingBoxKey.dynamicBadgeMode: dynamicBadge.index,
        SettingBoxKey.msgBadgeMode: messageBadge.index,
      });
      late _CountingMainController controller;
      var dynamicCallsDuringBuild = -1;
      var messageCallsDuringBuild = -1;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (_) {
              controller = _CountingMainController();
              Get.put<MainController>(controller);
              dynamicCallsDuringBuild = controller.dynamicCalls;
              messageCallsDuringBuild = controller.messageCalls;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(dynamicCallsDuringBuild, 0);
      expect(messageCallsDuringBuild, 0);
      expect(controller.dynamicCalls, expectedDynamic);
      expect(controller.messageCalls, expectedMessages);
      expect(controller.navigationBars, tabs);
      expect(
        controller.navigationBars[controller.selectedIndex.value],
        tabs.contains(defaultTab) ? defaultTab : tabs.first,
      );
      expect(
        controller.lastCheckUnreadAt,
        expectedMessages == 0 ? 0 : greaterThan(0),
      );

      await tester.pump();
      expect(controller.dynamicCalls, expectedDynamic);
      expect(controller.messageCalls, expectedMessages);
    });
  }

  testWidgets('disabling periodic dynamic checks keeps the initial request', (
    tester,
  ) async {
    await GStorage.setting.put(
      SettingBoxKey.checkDynamic,
      false,
    );
    late _CountingMainController controller;
    var dynamicCallsDuringBuild = -1;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (_) {
            controller = _CountingMainController();
            Get.put<MainController>(controller);
            dynamicCallsDuringBuild = controller.dynamicCalls;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(dynamicCallsDuringBuild, 0);
    expect(controller.dynamicCalls, 1);

    await tester.pump();
    expect(controller.dynamicCalls, 1);
    controller.checkUnreadDynamic();
    expect(controller.dynamicCalls, 1);
  });

  testWidgets('deferred requests do not wait for a pending message response', (
    tester,
  ) async {
    final pending = Completer<void>();
    late _CountingMainController controller;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (_) {
            controller = _CountingMainController()..messageResponse = pending;
            Get.put<MainController>(controller);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(controller.dynamicCalls, 1);
    expect(controller.messageCalls, 1);
    await tester.pump();
    expect(controller.dynamicCalls, 1);
    expect(controller.messageCalls, 1);
    pending.complete();
    await tester.pump();
  });
}

// 仅替换请求出口；使用真实 MainController 初始化、导航与 GetX 生命周期。
class _CountingMainController extends MainController {
  int dynamicCalls = 0;
  int messageCalls = 0;
  Completer<void>? messageResponse;
  final phases = <SchedulerPhase>[];

  @override
  void getUnreadDynamic() {
    dynamicCalls++;
    phases.add(SchedulerBinding.instance.schedulerPhase);
  }

  @override
  Future<void> queryUnreadMsg() {
    messageCalls++;
    phases.add(SchedulerBinding.instance.schedulerPhase);
    return messageResponse?.future ?? Future<void>.value();
  }
}

class _PendingBadgeSettings extends MemoryBox<dynamic> {
  Completer<void>? pendingMode;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (key == SettingBoxKey.msgBadgeMode) await pendingMode?.future;
    await super.put(key, value);
  }
}
