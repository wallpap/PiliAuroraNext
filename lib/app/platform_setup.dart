import 'dart:io';

import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/fullscreen.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/desktop_playback_windows.dart';
import 'package:pili_aurora_next/services/settings/window_preferences.dart';
import 'package:pili_aurora_next/services/webview_environment.dart';
import 'package:pili_aurora_next/platform/desktop/window_position.dart';
import 'package:pili_aurora_next/platform/android/max_screen_size.dart';
import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/platform/desktop/window_background.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

/// 初始化平台能力；Windows 网页环境按首次使用创建。
Future<void> initializePlatformServices() async {
  if (PlatformUtils.isMobile) {
    if (Platform.isAndroid) MaxScreenSize.init();
    await Future.wait([
      if (Pref.horizontalScreen) ?fullMode() else ?portraitUpMode(),
      setupServiceLocator(),
    ]);
  } else if (Platform.isWindows) {
    AppWebViewEnvironment.configure(
      userDataPath: path.join(appSupportDirPath, 'flutter_inappwebview'),
    );
  }
}

/// 配置移动端系统 UI，或创建并显示桌面应用窗口。
Future<void> initializePlatformWindow() async {
  if (PlatformUtils.isMobile) {
    await SystemChrome.setEnabledSystemUIMode(.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (Platform.isAndroid) {
      try {
        final mode = await FlutterDisplayMode.supported;
        final String? storageDisplay = GStorage.setting.get(
          SettingBoxKey.displayMode,
        );
        DisplayMode? displayMode;
        if (storageDisplay != null) {
          displayMode = mode.firstWhereOrNull(
            (e) => e.toString() == storageDisplay,
          );
        }
        await FlutterDisplayMode.setPreferredMode(
          displayMode ?? DisplayMode.auto,
        );
      } catch (error, stackTrace) {
        // 刷新率选择是可选能力，失败时保留系统模式并继续启动。
        logger.w('设置显示模式失败', error: error.runtimeType, stackTrace: stackTrace);
      }
    } else {
      await ScreenBrightnessPlatform.instance.setAutoReset(false);
    }
  } else if (PlatformUtils.isDesktop) {
    if (Platform.isWindows) {
      try {
        // 限制 raster scratch 的高水位；图片/IO 纹理与视频输出另有所有者。
        await SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          64 << 20,
        );
      } catch (error, stackTrace) {
        // 缓存预算是优化项，通道不可用时沿用引擎预算并继续创建窗口。
        logger.w(
          '设置绘制资源缓存预算失败',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      }
    }
    await windowManager.ensureInitialized();
    if (Platform.isWindows) {
      final (light, dark) = ThemeUtils.getAllTheme();
      final isDark =
          Pref.themeMode == ThemeMode.dark ||
          (Pref.themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      await DesktopWindowBackground.setThemeColor(
        DesktopPlaybackWindows.isPlayerWindow
            ? Colors.black
            : (isDark ? dark : light).scaffoldBackgroundColor,
      );
    }
    if (DesktopPlaybackWindows.isPlayerWindow) {
      final windows = DesktopPlaybackWindows.instance;
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          minimumSize: Size(320, 180),
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
          title: 'PiliAuroraNext Player',
          backgroundColor: Color(0xFF000000),
        ),
      );
      await windowManager.setBounds(windows.initialBounds!);
      await windowManager.setAlwaysOnTop(true);
      return;
    }

    const windowOptions = WindowOptions(
      minimumSize: Size(400, 720),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: Constants.appName,
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    final windowSize = WindowPreferences.size;
    await windowManager.setBounds(
      await calcWindowPosition(windowSize) & windowSize,
    );
    if (WindowPreferences.isMaximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  }
}
