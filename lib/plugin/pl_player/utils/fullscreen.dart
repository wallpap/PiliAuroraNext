import 'dart:async';
import 'dart:io' show Platform;

import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/platform/device_actions.dart';
import 'package:pili_aurora_next/platform/desktop/window_background.dart';
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;

bool _isDesktopFullScreen = false;
bool _desktopFullscreenInFlight = false;

bool get desktopFullscreenBlocksBounds =>
    _desktopFullscreenInFlight || _isDesktopFullScreen;

Future<bool> enterDesktopFullScreen({bool inAppFullScreen = false}) =>
    inAppFullScreen ? Future.value(true) : _setDesktopFullScreen(true);

Future<bool> exitDesktopFullScreen() => _setDesktopFullScreen(false);

@pragma('vm:notify-debugger-on-exception')
Future<bool> _setDesktopFullScreen(bool target) async {
  if (_isDesktopFullScreen == target) return true;
  _desktopFullscreenInFlight = true;
  try {
    await DesktopWindowBackground.setFullscreen(target);
    await const MethodChannel('com.alexmercerind/media_kit_video')
        .invokeMethod<void>(
          target ? 'Utils.EnterNativeFullscreen' : 'Utils.ExitNativeFullscreen',
        );
    _isDesktopFullScreen = target;
    return true;
  } catch (error, stackTrace) {
    await DesktopWindowBackground.setFullscreen(_isDesktopFullScreen);
    logger.w(
      target ? '进入原生全屏失败' : '退出原生全屏失败',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  } finally {
    _desktopFullscreenInFlight = false;
  }
}

List<DeviceOrientation>? _lastOrientation;
int _orientationRevision = 0;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  final previous = _lastOrientation;
  final revision = ++_orientationRevision;
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations).catchError((
    Object error,
    StackTrace stack,
  ) {
    if (_orientationRevision == revision) _lastOrientation = previous;
    Error.throwWithStackTrace(error, stack);
  });
}

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

bool _showSystemBar = true;
int _systemBarRevision = 0;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  final revision = ++_systemBarRevision;
  _showSystemBar = false;
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky)
      .catchError((Object error, StackTrace stack) {
        if (_systemBarRevision == revision) _showSystemBar = true;
        Error.throwWithStackTrace(error, stack);
      });
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  final revision = ++_systemBarRevision;
  _showSystemBar = true;
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  ).catchError((Object error, StackTrace stack) {
    if (_systemBarRevision == revision) _showSystemBar = false;
    Error.throwWithStackTrace(error, stack);
  });
}
