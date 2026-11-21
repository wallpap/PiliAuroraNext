import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

mixin DesktopWindowVisibilityListener
    on WindowListener, WidgetsBindingObserver {
  bool _minimized = false;
  AppLifecycleState? _lifecycle;

  bool get _visible =>
      !_minimized &&
      _lifecycle != AppLifecycleState.hidden &&
      _lifecycle != AppLifecycleState.paused &&
      _lifecycle != AppLifecycleState.detached;

  void onWindowVisibilityChanged(bool visible);

  void _setMinimized(bool minimized) {
    _minimized = minimized;
    onWindowVisibilityChanged(_visible);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    onWindowVisibilityChanged(_visible);
  }

  @override
  void onWindowMinimize() => _setMinimized(true);

  @override
  void onWindowRestore() => _setMinimized(false);

  @override
  void onWindowMaximize() => _setMinimized(false);

  @override
  void onWindowUnmaximize() => _setMinimized(false);
}
