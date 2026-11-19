import 'dart:async';

import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:pili_aurora_next/features/download/application/download_progress.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/features/download/data/download_repository.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/utils/download_path.dart';
import 'package:pili_aurora_next/app/back_navigation.dart';
import 'package:pili_aurora_next/app/desktop_playback_launch.dart';
import 'package:pili_aurora_next/app/desktop_theme.dart';
import 'package:pili_aurora_next/app/desktop_title_bar.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/widgets/app_viewport.dart';
import 'package:pili_aurora_next/common/widgets/back_detector.dart';
import 'package:pili_aurora_next/common/widgets/custom_toast.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/common/widgets/scroll_behavior.dart';
import 'package:pili_aurora_next/router/app_pages.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/desktop_playback_request.dart';
import 'package:pili_aurora_next/services/settings/window_preferences.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// 提供应用主题、本地化、路由、全局对话框和导航观察器。
class PiliAuroraNextApp extends StatefulWidget {
  const PiliAuroraNextApp({super.key, this.playbackRequest});
  final DesktopPlaybackRequest? playbackRequest;

  @override
  State<PiliAuroraNextApp> createState() => _PiliAuroraNextAppState();
}

class _PiliAuroraNextAppState extends State<PiliAuroraNextApp> {
  late final _showTitleBar = WindowPreference.showTitleBar.read();

  @override
  void dispose() {
    if (widget.playbackRequest == null) {
      unawaited(
        GStorage.close().then<void>((_) {}).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          logger.w(
            '关闭应用存储失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackRequest = widget.playbackRequest;
    final (light, dark) = ThemeUtils.getAllTheme();
    return ProviderScope(
      overrides: [
        downloadProgressStoreProvider.overrideWithValue(
          _DownloadProgressStore(),
        ),
        downloadRepositoryProvider.overrideWith(
          (ref) => DownloadRepository(
            rootPath: resolveDownloadPath,
            onReadError: (path, error, stack) => logger.w(
              '下载元数据读取或恢复异常: $path',
              error: error.runtimeType,
              stackTrace: stack,
            ),
          ),
        ),
        downloadClientProvider.overrideWithValue(Request.http11Dio),
        downloadBackgroundErrorProvider.overrideWithValue(
          SmartDialog.showToast,
        ),
      ],
      child: GetMaterialApp(
        title: Constants.appName,
        theme: light,
        darkTheme: dark,
        themeMode: ThemeUtils.themeMode = Pref.themeMode,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: const Locale("zh", "CN"),
        fallbackLocale: const Locale("zh", "CN"),
        supportedLocales: const [Locale("zh", "CN"), Locale("en", "US")],
        initialRoute: playbackRequest == null ? '/' : '/desktopPlayer',
        getPages: [
          ...Routes.getPages,
          if (playbackRequest case final request?)
            GetPage(
              name: '/desktopPlayer',
              page: () => DesktopPlaybackLaunch(request: request),
            ),
        ],
        defaultTransition: Pref.pageTransition,
        builder: FlutterSmartDialog.init(
          toastBuilder: CustomToast.new,
          loadingBuilder: LoadingWidget.new,
          notifyStyle: const FlutterSmartNotifyStyle(
            warningBuilder: NotifyWarning.new,
          ),
          builder: _builder,
        ),
        navigatorObservers: [
          DiagnosticRouteObserver(),
          routeObserver,
          FlutterSmartDialog.observer,
        ],
        scrollBehavior: PlatformUtils.isDesktop
            ? const CustomScrollBehavior()
            : null,
      ),
    );
  }

  Widget _builder(BuildContext context, Widget? child) {
    final playbackRequest = widget.playbackRequest;
    final viewport = AppViewport(
      uiScale: Pref.uiScale,
      textScale: Pref.defaultTextScale,
      child: child!,
    );
    return PlatformUtils.isDesktop
        ? DesktopWindowTheme(
            backgroundColor: playbackRequest == null ? null : Colors.black,
            child: BackDetector(
              onBack: handleAppBack,
              child: playbackRequest == null
                  ? DesktopWindowFrame(
                      showTitleBar: _showTitleBar,
                      child: viewport,
                    )
                  : viewport,
            ),
          )
        : viewport;
  }
}

class _DownloadProgressStore implements DownloadProgressStore {
  @override
  int? read(int cid) => GStorage.watchProgress.get(cid.toString());

  @override
  Future<void> remove(Iterable<int> cids) =>
      GStorage.watchProgress.deleteAll(cids.map((cid) => cid.toString()));
}
