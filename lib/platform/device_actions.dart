import 'dart:io' show OSError, Platform, exit;

import 'package:pili_aurora_next/platform/android/bindings.g.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, Size;
import 'package:win32/win32.dart' as kernel32;

abstract final class DeviceUtils {
  static void terminateApp() {
    if (Platform.isWindows) {
      final result = kernel32.TerminateProcess(kernel32.GetCurrentProcess(), 0);
      if (!result.value) throw OSError('结束应用进程失败', result.error);
    } else {
      exit(0);
    }
  }

  static final int sdkInt = AndroidHelper.sdkInt();

  static bool get isTablet {
    return size.shortestSide >= 600;
  }

  static Size get size {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  static String get platformName => PlatformUtils.isDesktop
      ? 'desktop'
      : isTablet
      ? 'pad'
      : 'phone';
}
