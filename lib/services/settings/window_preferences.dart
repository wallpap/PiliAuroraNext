import 'dart:ui';

import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

enum WindowPreference {
  showTitleBar(SettingBoxKey.showWindowTitleBar, defaultValue: true),
  showTrayIcon(SettingBoxKey.showTrayIcon, defaultValue: true),
  minimizeOnExit(SettingBoxKey.minimizeOnExit, defaultValue: true),
  directExitOnBack(SettingBoxKey.directExitOnBack),
  pauseOnMinimize(SettingBoxKey.pauseOnMinimize);

  const WindowPreference(this.key, {this.defaultValue = false});

  final String key;
  final bool defaultValue;

  static final _saving = <WindowPreference, bool>{};

  bool read() =>
      _saving[this] ??
      switch (GStorage.setting.get(key)) {
        final bool value => value,
        _ => defaultValue,
      };

  Future<void> save(bool value) async {
    if (_saving.containsKey(this)) {
      throw StateError('窗口偏好正在保存');
    }
    _saving[this] = read();
    try {
      await GStorage.setting.put(key, value);
    } finally {
      _saving.remove(this);
    }
  }
}

abstract final class WindowPreferences {
  static const defaultSize = Size(1180, 720);

  static Size get size {
    final pair = _readPair(SettingBoxKey.windowSize);
    if (pair == null || pair.dx <= 0 || pair.dy <= 0) return defaultSize;
    return Size(pair.dx, pair.dy);
  }

  static Offset? get position => _readPair(SettingBoxKey.windowPosition);

  static Offset? _readPair(String key) => switch (GStorage.setting.get(key)) {
    [num first, num second] when first.isFinite && second.isFinite => Offset(
      first.toDouble(),
      second.toDouble(),
    ),
    _ => null,
  };

  static bool get isMaximized =>
      GStorage.setting.get(SettingBoxKey.isWindowMaximized) == true;

  static Future<void> saveMaximized(bool maximized) =>
      GStorage.setting.put(SettingBoxKey.isWindowMaximized, maximized);

  static Future<void> savePosition(Offset position) => GStorage.setting.put(
    SettingBoxKey.windowPosition,
    [position.dx, position.dy],
  );

  static Future<void> saveBounds(Rect bounds) => GStorage.setting.putAll({
    SettingBoxKey.windowSize: [bounds.width, bounds.height],
    SettingBoxKey.windowPosition: [bounds.left, bounds.top],
  });

  static bool hideOnClose({required bool trayAvailable}) =>
      trayAvailable && WindowPreference.minimizeOnExit.read();

  static bool returnToFirstTab(int selectedIndex) =>
      selectedIndex != 0 && !WindowPreference.directExitOnBack.read();
}
