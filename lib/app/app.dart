import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:pili_aurora_next/services/download/download_repository.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/utils/path_utils.dart';
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
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// 提供应用主题、本地化、路由、全局对话框和导航观察器。
class PiliAuroraNextApp extends StatelessWidget {
  const PiliAuroraNextApp({super.key, this.playbackRequest});
  final DesktopPlaybackRequest? playbackRequest;

  @override
  Widget build(BuildContext context) {
    final (light, dark) = ThemeUtils.getAllTheme();
    return ProviderScope(
      overrides: [
        downloadRepositoryProvider.overrideWith(
          (ref) => DownloadRepository(
            rootPath: () => downloadPath,
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
                      showTitleBar: Pref.showWindowTitleBar,
                      child: viewport,
                    )
                  : viewport,
            ),
          )
        : viewport;
  }
}
