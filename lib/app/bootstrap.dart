import 'dart:async';
import 'dart:io';

import 'package:pili_aurora_next/plugin/pl_player/playback/presentation_profile.dart';

import 'package:pili_aurora_next/app/app.dart';
import 'package:pili_aurora_next/app/app_paths.dart';
import 'package:pili_aurora_next/app/back_navigation.dart';
import 'package:pili_aurora_next/app/platform_setup.dart';
import 'package:pili_aurora_next/app/startup.dart';
import 'package:pili_aurora_next/app/startup_failure.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/application/coin_balance.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:pili_aurora_next/features/danmaku/application/work_quota.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/playback/application/offline_progress.dart';
import 'package:pili_aurora_next/features/playback/domain/media/offline_watch_progress.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/platform/device_actions.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/app_exit.dart';
import 'package:pili_aurora_next/services/desktop_playback_windows.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart'
    show PlaybackShutdownOutcome;
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/build_config.dart';
import 'package:pili_aurora_next/common/widgets/scale_app.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/services/app_icon.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/cache/image_cache.dart';
import 'package:pili_aurora_next/core/time/date_format.dart';
import 'package:pili_aurora_next/services/settings/font_assets.dart';
import 'package:pili_aurora_next/http/loading_state.dart' as font_result;
import 'package:pili_aurora_next/services/diagnostics/report_handler.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';
import 'package:pili_aurora_next/services/webview_environment.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

/// 初始化本地资源和平台服务，配置异常捕获后挂载应用根 Widget。
Future<StartupResult> bootstrapApplication([
  List<String> arguments = const [],
]) async {
  final progress = StartupProgress();
  final windows = DesktopPlaybackWindows.instance;
  final playerWindow =
      Platform.isWindows &&
      arguments.firstOrNull == DesktopPlaybackWindows.argument;
  final startupSettled = Completer<void>();
  final cleanup = <AppExitCleanup>[];
  final appExit = AppExit(
    cleanup: cleanup,
    flushDiagnostics: playerWindow ? null : Diagnostics.instance.shutdown,
    terminate: playerWindow ? windows.onWindowClose : DeviceUtils.terminateApp,
  );
  AppExit.application = appExit;
  if (playerWindow) {
    windows.onPlayerClose = () async {
      await startupSettled.future;
      await appExit.release();
    };
  }
  final result = await progress.run(
    () => _bootstrapApplication(progress, appExit, cleanup, playerWindow),
  );
  if (result is StartupFailure) {
    exitCode = 1;
    logger.e(
      '应用启动失败：${result.phase.label}',
      error: result.cause.runtimeType,
      stackTrace: result.stackTrace,
    );
    startupSettled.complete();
    await appExit.release();
    if (playerWindow) exit(1);
    try {
      await showStartupFailure(result);
    } catch (error, stackTrace) {
      logger.e('启动错误页显示失败', error: error.runtimeType, stackTrace: stackTrace);
      Error.throwWithStackTrace(result, result.stackTrace);
    }
  } else {
    startupSettled.complete();
  }
  return result;
}

Future<void> _bootstrapApplication(
  StartupProgress progress,
  AppExit appExit,
  List<AppExitCleanup> cleanup,
  bool playerWindow,
) async {
  final windows = DesktopPlaybackWindows.instance;
  final diagnostics = Diagnostics.instance;
  final previousHttpOverrides = HttpOverrides.current;
  var storageStarted = false;
  var startupComplete = false;
  var overridesInstalled = false;
  var keyHandlerInstalled = false;
  cleanup.addAll([
    (
      'keyboard',
      () {
        if (keyHandlerInstalled) {
          FocusManager.instance.removeEarlyKeyEventHandler(handleAppKeyEvent);
        }
      },
    ),
    ('shutdown timer', closeApplicationShutdownTimer),
    ('messaging', Messaging.closeApplicationSession),
    if (playerWindow) ('player bounds', windows.preparePlayerClose),
    if (!playerWindow && Platform.isWindows)
      ('diagnostics writes', diagnostics.resumeWrites),
    if (!playerWindow && Platform.isWindows)
      ('playback windows', windows.closeAll),
    if (!playerWindow && Platform.isWindows)
      ('offline progress', _saveOfflineProgress),
    if (!playerWindow)
      (
        'platform audio',
        () => closePlatformAudioSession().timeout(const Duration(seconds: 3)),
      ),
    ('playback', () => _releasePlayback(playerWindow: playerWindow)),
    ('danmaku', DanmakuWorkQuota.disposeProcessQuota),
    ('requests', Request.close),
    ('account profile', AccountProfile.closeApplication),
    ('coin balance', CoinBalance.closeApplication),
    ('history', HistoryLibrary.closeApplication),
    ('favorites', FavoriteLibrary.closeApplication),
    ('watch later', LaterLibrary.closeApplication),
    (
      'HTTP overrides',
      () {
        if (overridesInstalled) HttpOverrides.global = previousHttpOverrides;
      },
    ),
    (
      'webview',
      () => AppWebViewEnvironment.close().timeout(const Duration(seconds: 3)),
    ),
    ('image cache', CacheManager.close),
    if (!playerWindow)
      (
        'compact',
        () async {
          if (startupComplete) await GStorage.compact();
        },
      ),
    (
      'storage',
      () async {
        if (storageStarted) await GStorage.close();
      },
    ),
    if (playerWindow) ...[
      (
        'diagnostics',
        () => diagnostics.shutdown().timeout(const Duration(seconds: 3)),
      ),
      (
        'player IPC',
        () => windows.finishPlayerConnection(startupFailed: !startupComplete),
      ),
    ],
  ]);
  initializePresentationEngineConfiguration();
  ScaledWidgetsFlutterBinding.ensureInitialized();
  progress.phase = StartupPhase.supportPath;
  await initializeSupportPath();
  progress.phase = StartupPhase.diagnostics;
  await LoggerUtils.prepare(
    windowId: playerWindow
        ? int.parse(Platform.environment['PILIAURORANEXT_WINDOW_ID']!)
        : null,
  );
  if (!playerWindow) {
    Diagnostics.instance
      ..onSettingsChanged = windows.syncDiagnosticSettings
      ..pauseChildren = windows.pauseWindowDiagnostics
      ..clearChildren = windows.clearWindowDiagnostics
      ..resumeChildren = windows.resumeWindowDiagnostics;
  }
  progress.phase = StartupPhase.playerConnection;
  final initialization = playerWindow ? await windows.connectPlayer() : null;
  if (playerWindow) {
    Diagnostics.instance.forwardRecord = windows.sendDiagnosticRecord;
    Diagnostics.instance.forwardFlush = windows.flushDiagnostics;
  }
  progress.phase = StartupPhase.engine;
  MediaKit.ensureInitialized();
  progress.phase = StartupPhase.storage;
  storageStarted = true;
  await GStorage.init(memorySnapshot: initialization?.storage);
  FeedLayoutPreferences.initialize();
  AppIcon.load();
  if (playerWindow) {
    await GStorage.setting.putAll({
      SettingBoxKey.desktopVolume: ?windows.initialVolume,
      SettingBoxKey.autoPlayEnable: true,
      SettingBoxKey.enableAutoEnter: false,
      SettingBoxKey.preInitPlayer: false,
      SettingBoxKey.showVideoReply: false,
      SettingBoxKey.showBangumiReply: false,
      SettingBoxKey.showRelatedVideo: false,
      SettingBoxKey.pageTransition: Transition.noTransition.index,
    });
  }
  ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
  progress.phase = StartupPhase.diagnostics;
  await LoggerUtils.initialize();
  if (playerWindow) await windows.applyDiagnosticSettings();
  progress.phase = StartupPhase.resources;
  await Future.wait([
    initializeTemporaryPath(),
    CacheManager.ensureInitialized(directory: windows.cacheDirectory),
    FontUtils.init().then<void>((result) {
      if (result case font_result.Error(:final cause, :final stackTrace)) {
        logger.w(
          '自定义字体加载失败，使用默认字体',
          error: cause?.runtimeType,
          stackTrace: stackTrace,
        );
      }
    }),
  ]);
  HttpOverrides.global = _CustomHttpOverrides();
  overridesInstalled = true;
  if (Pref.badCertificateCallback) {
    logger.w('已显式禁用 TLS 证书验证，仅应用于受控调试；请在调试结束后恢复验证');
  }

  // Windows 只登记网页数据目录，首次进入网页时再同步当前账号 Cookie。
  progress.phase = StartupPhase.platformServices;
  if (!playerWindow) await initializePlatformServices();

  progress.phase = StartupPhase.requests;
  Request();
  Request.setCookie(syncWebView: !playerWindow && !Platform.isWindows);
  unawaited(
    CoinBalance.instance.restore().catchError((Object error, StackTrace stack) {
      logger.w('启动余额同步失败', error: error.runtimeType, stackTrace: stack);
    }),
  );
  if (!playerWindow) {
    unawaited(
      HistoryLibrary.legacy.syncActiveAccountStatus().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        logger.w(
          '启动历史状态同步失败',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      }),
    );
  }
  windows.setLocalMuted = (muted) async {
    await PlPlayerController.instance?.setMuted(muted);
  };

  SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);

  progress.phase = StartupPhase.window;
  if (PlatformUtils.isDesktop) {
    FocusManager.instance.addEarlyKeyEventHandler(handleAppKeyEvent);
    keyHandlerInstalled = true;
  }
  await initializePlatformWindow();
  if (playerWindow) {
    await windows.watchPlayerWindow();
  }

  progress.phase = StartupPhase.application;
  if (Pref.dynamicColor) {
    await ThemeUtils.initPlatformState();
  }

  // 始终安装异常捕获，日志等级可即时切换。
  final customParameters = {
    'Build Time': DateFormatUtils.format(
      BuildConfig.buildTime,
      format: DateFormatUtils.longFormatDs,
    ),
    'Commit Hash': BuildConfig.commitHash,
    'MPV Api Version':
        '${NativePlayer.apiVersion >> 16}.${NativePlayer.apiVersion & 0xFFFF}',
  };

  Catcher2(
    [DiagnosticReportHandler()],
    PiliAuroraNextApp(exit: appExit, playbackRequest: initialization?.request),
    logger: (level, message, {error, stackTrace}) {
      final log = switch (level) {
        ReportLogLevel.debug => logger.d,
        ReportLogLevel.info => logger.i,
        ReportLogLevel.warning => logger.w,
        ReportLogLevel.error => logger.e,
      };
      log(message, error: error, stackTrace: stackTrace);
    },
    customParameters: customParameters,
  );
  startupComplete = true;
  if (!playerWindow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        unawaited(
          AppIcon.syncLauncher().catchError((Object error, StackTrace stack) {
            logger.w('同步桌面图标失败', error: error.runtimeType, stackTrace: stack);
          }),
        );
      }
      final diagnostics = Diagnostics.instance;
      if (shouldWarnAboutDiagnosticRecording(
        tracing: diagnostics.tracing,
        level: diagnostics.level,
        playerLevel: diagnostics.playerLevel,
      )) {
        SmartDialog.showToast(
          '性能记录或详细日志已启用，如不需要，请关闭并清理',
          displayTime: const Duration(seconds: 5),
        );
      }
    });
  }
}

({int cid, OfflineWatchProgress progress})? _currentOfflineProgress(
  PlPlayerController? player,
) {
  final cid = player?.cid;
  if (player == null ||
      cid == null ||
      !player.isFileSource ||
      player.activePlaybackOwner?.ownsLoadedContent('file:$cid') != true) {
    return null;
  }
  final progress = player.isCompleted
      ? const OfflineWatchProgress.completed()
      : OfflineWatchProgress.at(player.positionInMilliseconds);
  return (cid: cid, progress: progress);
}

Future<void> _saveOfflineProgress() async {
  if (_currentOfflineProgress(PlPlayerController.instance) case final saved?) {
    await OfflineProgress.record(saved.cid, saved.progress);
  }
}

Future<void> _releasePlayback({required bool playerWindow}) async {
  final player = PlPlayerController.instance;
  if (player == null) return;
  if (playerWindow) {
    if (_currentOfflineProgress(player) case final saved?) {
      DesktopPlaybackWindows.instance.savePlaybackProgress(
        saved.cid,
        saved.progress,
      );
    }
  }
  final result = await player.shutdownPlaybackFacade();
  if (result.outcome == PlaybackShutdownOutcome.cleanupIncomplete) {
    logger.w('播放器退出清理未完成', error: result.failure);
    await player.playbackReleased.timeout(const Duration(seconds: 3));
  } else {
    await player.playbackReleased;
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // ..maxConnectionsPerHost = 32
    /// The default value is 15 seconds.
    //   ..idleTimeout = const Duration(seconds: 15);
    if (Pref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
