import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/services/settings/window_preferences.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

void main() {
  final settings = _OptimisticSettings();
  setUpAll(() => GStorage.setting = settings);
  setUp(() async {
    settings.pending = null;
    await settings.clear();
  });

  test('旧开关键与布尔值保持兼容，损坏值只在读取时应用默认值', () async {
    const switches = [
      (WindowPreference.showTitleBar, 'showWindowTitleBar', true),
      (WindowPreference.showTrayIcon, 'showTrayIcon', true),
      (WindowPreference.minimizeOnExit, 'minimizeOnExit', true),
      (WindowPreference.directExitOnBack, 'directExitOnBack', false),
      (WindowPreference.pauseOnMinimize, 'pauseOnMinimize', false),
    ];
    for (final (preference, key, defaultValue) in switches) {
      expect(preference.read(), defaultValue);
      await settings.put(key, !defaultValue);
      expect(preference.read(), !defaultValue);
      await preference.save(defaultValue);
      expect(settings.get(key), defaultValue);
      await settings.put(key, 'invalid');
      expect(preference.read(), defaultValue);
      expect(settings.get(key), 'invalid');
    }
  });

  test('普通关闭只有在托盘可用时才能最小化，且等保存确认后生效', () async {
    expect(WindowPreferences.hideOnClose(trayAvailable: false), isFalse);
    expect(WindowPreferences.hideOnClose(trayAvailable: true), isTrue);

    final pending = settings.pending = Completer<void>();
    final saving = WindowPreference.minimizeOnExit.save(false);
    expect(settings.get('minimizeOnExit'), isFalse);
    expect(WindowPreferences.hideOnClose(trayAvailable: true), isTrue);
    pending.complete();
    await saving;
    expect(WindowPreferences.hideOnClose(trayAvailable: true), isFalse);
  });

  test('主页返回默认先切首个标签，保存失败保持旧行为且可重试', () async {
    expect(WindowPreferences.returnToFirstTab(0), isFalse);
    expect(WindowPreferences.returnToFirstTab(2), isTrue);
    final pending = settings.pending = Completer<void>();
    final saving = WindowPreference.directExitOnBack.save(true);
    expect(WindowPreferences.returnToFirstTab(2), isTrue);
    final failure = expectLater(saving, throwsStateError);
    pending.completeError(StateError('synthetic storage error'));
    await failure;
    expect(WindowPreferences.returnToFirstTab(2), isTrue);
    settings.pending = null;
    await WindowPreference.directExitOnBack.save(true);
    expect(WindowPreferences.returnToFirstTab(2), isFalse);
    expect(WindowPreferences.returnToFirstTab(0), isFalse);
  });

  test('窗口移动、缩放与最大化沿用旧键与存储结构', () async {
    expect(WindowPreferences.isMaximized, isFalse);
    await WindowPreferences.saveBounds(
      const Rect.fromLTWH(-960, 40, 1000, 760),
    );
    expect(settings.get('windowSize'), [1000.0, 760.0]);
    expect(settings.get('windowPosition'), [-960.0, 40.0]);
    await WindowPreferences.savePosition(const Offset(30, 10));
    expect(WindowPreferences.size, const Size(1000, 760));
    expect(WindowPreferences.position, const Offset(30, 10));
    await WindowPreferences.saveMaximized(true);
    expect(settings.get('isWindowMaximized'), isTrue);
    expect(WindowPreferences.isMaximized, isTrue);
    await WindowPreferences.saveMaximized(false);
    expect(WindowPreferences.isMaximized, isFalse);
  });
}

class _OptimisticSettings extends MemoryBox<dynamic> {
  Completer<void>? pending;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    final previous = data[key];
    data[key] = value;
    try {
      await pending?.future;
    } catch (_) {
      if (previous == null) {
        data.remove(key);
      } else {
        data[key] = previous;
      }
      rethrow;
    }
  }
}
