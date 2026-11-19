import 'dart:async';
import 'dart:io';

import 'package:pili_aurora_next/common/assets.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/floating_navigation_bar.dart';
import 'package:pili_aurora_next/common/widgets/flutter/pop_scope.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/inactive_paint_cleanup.dart';
import 'package:pili_aurora_next/common/widgets/main_layout.dart';
import 'package:pili_aurora_next/common/widgets/main_navigation_icon.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';
import 'package:pili_aurora_next/features/app_shell/application/shell_badges.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/scroll_bars.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/shell_actions.dart';
import 'package:pili_aurora_next/features/search/application/search_hint.dart';
import 'package:pili_aurora_next/models/common/nav_bar_config.dart';
import 'package:pili_aurora_next/pages/dynamics/view.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/pages/mine/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';
import 'package:pili_aurora_next/services/app_exit.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/services/desktop_playback_windows.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/settings/navigation_preferences.dart';
import 'package:pili_aurora_next/services/settings/window_preferences.dart';
import 'package:pili_aurora_next/services/windows_update_exit.dart';
import 'package:pili_aurora_next/utils/android/android_helper.dart';
import 'package:pili_aurora_next/utils/app_scheme.dart';
import 'package:pili_aurora_next/utils/device_utils.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/mobile_observer.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends PopScopeState<MainApp>
    with
        RouteAware,
        RouteAwareMixin,
        WidgetsBindingObserver,
        WindowListener,
        SingleTickerProviderStateMixin {
  late final NavigationLayoutPreferences _layout;
  late final List<NavigationBarType> _navigation;
  late final ValueNotifier<int> _selectedIndex;
  TabController? _tabs;
  PageController? _pages;
  late final ShellScrollBars _bars;
  late final VoidCallback _unregisterDiagnostics;
  late final ProviderSubscription<ShellBadges> _badgesSub;
  late final VoidCallback _detachBadges;
  ProviderSubscription<SearchHint>? _hintSub;
  ShellBadges get _badges => _badgesSub.read();
  HomePageActions? _home;
  ScrollOrRefreshMixin? _dynamics;
  DateTime? _lastReselect;
  NavigationBarType get _selectedTab => _navigation[_selectedIndex.value];
  bool get _hasHome => _navigation.contains(NavigationBarType.home);
  ScrollOrRefreshMixin? get dynamicsHandle => _dynamics;

  bool showDestination(NavigationBarType destination) {
    if (!mounted) return false;
    final index = _navigation.indexOf(destination);
    if (index < 0) return false;
    if (_selectedIndex.value != index) _selectTab(index);
    return true;
  }

  late EdgeInsets _padding;
  late ColorScheme _colorScheme;
  Brightness? _brightness;
  tray.TrayIcon? _trayIcon;
  tray.ListenerId? _trayListenerId;
  tray.Image? _trayImage;
  tray.Menu? _trayMenu;
  tray.MenuItem? _trayShowItem;
  tray.MenuItem? _trayExitItem;
  late final _exit = AppExit(
    cleanup: [
      ('shutdown timer', closeApplicationShutdownTimer),
      ('tray', _disposeTray),
      // 小窗会回传播放进度和窗口位置，先关闭小窗再关闭主进程存储。
      if (Platform.isWindows) ...[
        ('windows', DesktopPlaybackWindows.instance.closeAll),
        (
          'progress',
          () async {
            final player = PlPlayerController.instance;
            if (player != null && player.isFileSource && player.cid != null) {
              await GStorage.watchProgress.put(
                player.cid.toString(),
                player.positionInMilliseconds,
              );
            }
          },
        ),
        (
          'player',
          () async {
            final result = await PlPlayerController.instance
                ?.shutdownPlaybackFacade();
            if (result?.outcome == PlaybackShutdownOutcome.cleanupIncomplete) {
              logger.w('主窗口播放器退出清理未完成', error: result?.failure);
            }
          },
        ),
      ],
      ('compact', GStorage.compact),
      ('storage', GStorage.close),
    ],
    terminate: DeviceUtils.exitApp,
  );
  bool get _isClosing => _exit.isClosing;
  PlaybackOwner? _minimizeOwner;
  PlaybackInhibitorToken? _minimizeToken;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    _layout = NavigationLayoutPreferences();
    final (:tabs, :index) = NavigationPreferences.read();
    _navigation = tabs;
    _selectedIndex = ValueNotifier(index);
    if (_layout.animatePages) {
      _tabs = TabController(
        vsync: this,
        initialIndex: index,
        length: tabs.length,
      );
    } else {
      _pages = PageController(initialPage: index);
    }
    _bars = ShellScrollBars(
      hideInstantly: _layout.hideInstantly,
      hideTopBar: !_layout.forceSideBar && _layout.hideTopBar && _hasHome,
      hideBottomBar:
          !_layout.forceSideBar && _layout.hideBottomBar && tabs.length > 1,
    );
    final container = ProviderScope.containerOf(context, listen: false);
    _badgesSub = container.listen(shellBadgesProvider, (_, _) {});
    _detachBadges = _badges.attach(
      hasHome: _hasHome,
      hasDynamics: tabs.contains(NavigationBarType.dynamics),
    );
    _unregisterDiagnostics = Diagnostics.instance.register(
      'mainPage',
      () => {'page': _selectedTab.name},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_layout.checkUpdates) unawaited(Update.checkUpdate());
      _badges.start(onDynamics: _selectedTab == .dynamics);
    });
    Assets.iconStyle.addListener(_onIconStyleChanged);
    addObserverMobile(this);
    if (PlatformUtils.isDesktop) {
      if (Platform.isWindows) WindowsUpdateExit.setHandler(_onClose);
      windowManager
        ..addListener(this)
        ..setPreventClose(true);
      if (WindowPreference.showTrayIcon.read()) {
        _handleTray();
      }
    }
    PiliScheme.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    _colorScheme = ColorScheme.of(context);
    final brightness = _colorScheme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        _updateTrayImage(brightness);
      }
    }
    _bars.useBottomNavigation =
        !_layout.forceSideBar && MediaQuery.sizeOf(context).isPortrait;
  }

  void _checkHomeHint() {
    if (!_hasHome) return;
    final container = ProviderScope.containerOf(context, listen: false);
    _hintSub ??= container.listen(searchHintProvider, (_, _) {});
    _hintSub!.read().refreshIfDue();
  }

  void _refreshOnResume() {
    _badges.checkDynamics();
    if (_selectedTab == .home) _checkHomeHint();
    if (!_bars.useBottomNavigation || _selectedTab == .home) {
      _badges.checkMessages();
    }
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _refreshOnResume();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOnResume();
    }
  }

  @override
  void dispose() {
    _unregisterDiagnostics();
    _detachBadges();
    _badgesSub.close();
    _hintSub?.close();
    _selectedIndex.dispose();
    _tabs?.dispose();
    _pages?.dispose();
    _bars.dispose();
    Assets.iconStyle.removeListener(_onIconStyleChanged);
    if (Platform.isWindows) WindowsUpdateExit.setHandler(null);
    if (PlatformUtils.isDesktop) {
      _disposeTray();
      windowManager.removeListener(this);
      _releaseMinimizeInhibitor();
    }
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    WindowPreferences.saveMaximized(true);
  }

  @override
  void onWindowUnmaximize() {
    WindowPreferences.saveMaximized(false);
  }

  @override
  Future<void> onWindowMoved() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Offset offset = await windowManager.getPosition();
    await WindowPreferences.savePosition(offset);
  }

  @override
  Future<void> onWindowResized() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Rect bounds = await windowManager.getBounds();
    await WindowPreferences.saveBounds(bounds);
  }

  @override
  void onWindowClose() {
    if (_isClosing) return;
    if (WindowPreferences.hideOnClose(trayAvailable: _trayIcon != null)) {
      _hide();
      _onHideWindow();
    } else {
      _requestClose();
    }
  }

  Future<void> _onClose() => _exit.close();

  void _requestClose() {
    unawaited(
      _onClose().catchError((Object error, StackTrace stackTrace) {
        if (mounted) SmartDialog.showToast('退出应用失败，请重试');
      }),
    );
  }

  @override
  void onWindowMinimize() {
    _onHideWindow();
  }

  @override
  void onWindowRestore() {
    _releaseMinimizeInhibitor();
  }

  void _onHideWindow() {
    final player = PlPlayerController.instance;
    if (player == null ||
        !player.pauseOnMinimize.value ||
        !player.playerStatus.isPlaying) {
      return;
    }
    final owner = player.activePlaybackOwner;
    if (owner == null || identical(_minimizeOwner, owner)) return;
    _releaseMinimizeInhibitor();
    _minimizeOwner = owner;
    _minimizeToken = owner.acquireInhibitor(PlaybackInhibitorSource.system);
  }

  void _releaseMinimizeInhibitor() {
    final owner = _minimizeOwner;
    final token = _minimizeToken;
    _minimizeOwner = null;
    _minimizeToken = null;
    if (owner != null && token != null) {
      unawaited(owner.releaseInhibitor(token));
    }
  }

  double? _opacity;

  Future<void>? _setOpacity(double opacity) {
    if (Platform.isWindows && _opacity != opacity) {
      _opacity = opacity;
      return windowManager.setOpacity(opacity);
    }
    return null;
  }

  @override
  Future<void>? onWindowFocus() {
    return _setOpacity(1.0);
  }

  /// https://github.com/leanflutter/window_manager/issues/571
  Future<void> _hide() async {
    await _setOpacity(0.0);
    await windowManager.hide();
  }

  Future<void> _show() async {
    if (!mounted || _isClosing) return;
    _releaseMinimizeInhibitor();
    await windowManager.show();
  }

  void _scheduleClose() {
    if (_isClosing) return;
    // Windows 在原生菜单回调中派发菜单项事件，先让回调返回再释放菜单和关闭存储。
    Timer.run(_requestClose);
  }

  void _disposeTray() {
    final trayIcon = _trayIcon;
    final listenerId = _trayListenerId;
    final trayMenu = _trayMenu;
    final showItem = _trayShowItem;
    final exitItem = _trayExitItem;
    final trayImage = _trayImage;
    _trayIcon = null;
    _trayListenerId = null;
    _trayMenu = null;
    _trayShowItem = null;
    _trayExitItem = null;
    _trayImage = null;
    if (trayIcon != null) {
      if (listenerId != null) trayIcon.removeListener(listenerId);
      trayIcon.dispose();
    }
    trayMenu?.dispose();
    showItem?.dispose();
    exitItem?.dispose();
    trayImage?.dispose();
  }

  Future<void> _handleTrayIconClick() async {
    final visible = await windowManager.isVisible();
    if (!mounted || _isClosing) return;
    if (visible) {
      _onHideWindow();
      _hide();
    } else {
      _show();
    }
  }

  void _handleTray() {
    try {
      _initializeTray();
    } catch (error, stack) {
      logger.w('创建托盘失败', error: error.runtimeType, stackTrace: stack);
      try {
        _disposeTray();
      } catch (error, stack) {
        logger.w('清理托盘失败', error: error.runtimeType, stackTrace: stack);
      }
    }
  }

  void _initializeTray() {
    final trayIcon = _trayIcon = tray.TrayIcon.create();
    if (trayIcon == null) return;
    final trayImage = _trayImage = tray.ImageAsset.fromAsset(
      Assets.themed(
        Assets.logoIco,
        _brightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
    );
    final trayMenu = _trayMenu = tray.Menu.create();
    final showItem = _trayShowItem = tray.MenuItem.createWithLabelAndType(
      '显示窗口',
      tray.MenuItemType.normal,
    );
    final exitItem = _trayExitItem = tray.MenuItem.createWithLabelAndType(
      '退出 ${Constants.appName}',
      tray.MenuItemType.normal,
    );
    if (trayImage == null ||
        trayMenu == null ||
        showItem == null ||
        exitItem == null) {
      _disposeTray();
      return;
    }

    _trayListenerId = trayIcon.addListener((event) {
      if (event is tray.TrayIconClickedEvent) {
        unawaited(_handleTrayIconClick());
      }
    });
    showItem.addListener((event) {
      if (event is tray.MenuItemClickedEvent) unawaited(_show());
    });
    exitItem.addListener((event) {
      if (event is tray.MenuItemClickedEvent) _scheduleClose();
    });
    trayMenu
      ..addItem(showItem)
      ..addSeparator()
      ..addItem(exitItem);
    trayIcon
      ..icon = trayImage
      ..setTooltip(Constants.appName)
      ..setContextMenu(trayMenu)
      ..setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
    if (!trayIcon.setVisible(true)) _disposeTray();
  }

  void _updateTrayImage(Brightness brightness) {
    final trayIcon = _trayIcon;
    if (trayIcon == null) return;
    final image = tray.ImageAsset.fromAsset(
      Assets.themed(Assets.logoIco, brightness),
    );
    if (image == null) return;
    trayIcon.icon = image;
    final previous = _trayImage;
    _trayImage = image;
    previous?.dispose();
  }

  void _onIconStyleChanged() => _updateTrayImage(
    _brightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      PiliAndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (WindowPreferences.returnToFirstTab(_selectedIndex.value)) {
      _selectTab(0);
      _bars.reveal();
    } else {
      _onBack();
    }
  }

  void _openMine() {
    final index = _navigation.indexOf(.mine);
    if (index >= 0) {
      _selectTab(index);
    } else {
      openMinePage(showShellActions: !_hasHome);
    }
  }

  Future<void> _refreshSelectedPage() async {
    try {
      switch (_selectedTab) {
        case .home:
          await _home?.refresh();
        case .dynamics:
          await _dynamics?.onRefresh();
        case .mine:
          break;
      }
    } catch (error, stackTrace) {
      logger.w('刷新主页面失败', error: error, stackTrace: stackTrace);
    }
  }

  void _selectTab(int index) {
    feedBack();
    if (_selectedIndex.value == index) {
      final now = DateTime.now();
      final last = _lastReselect;
      _lastReselect = now;
      if (last != null &&
          now.difference(last) < const Duration(milliseconds: 500)) {
        ActionThrottle.run(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          () => unawaited(_refreshSelectedPage()),
        );
      } else if (_selectedTab == .home) {
        _home?.toTopOrRefresh();
      } else if (_selectedTab == .dynamics) {
        _dynamics?.toTopOrRefresh();
      }
      return;
    }
    _selectedIndex.value = index;
    _tabs?.animateTo(index);
    _pages?.jumpToPage(index);
    final tab = _selectedTab;
    Diagnostics.instance.log(
      DiagnosticLogLevel.debug,
      'pageSwitch',
      '切换主页面',
      details: {'page': tab.name},
    );
    if (tab == .home) {
      _checkHomeHint();
      _badges.checkMessages();
    } else if (tab == .dynamics) {
      _badges.clearDynamics();
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_navigation.length > 1) {
      if (_layout.floatingNavBar) {
        bottomNav = ValueListenableBuilder(
          valueListenable: _selectedIndex,
          builder: (context, index, _) => FloatingNavigationBar(
            onDestinationSelected: _selectTab,
            selectedIndex: index,
            destinations: _navigation
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_layout.materialNavBar) {
        bottomNav = ValueListenableBuilder(
          valueListenable: _selectedIndex,
          builder: (context, index, _) => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _selectTab,
            selectedIndex: index,
            destinations: _navigation
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = ValueListenableBuilder(
          valueListenable: _selectedIndex,
          builder: (context, index, _) => BottomNavigationBar(
            currentIndex: index,
            onTap: _selectTab,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _navigation
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      // 底栏内容不随滚动改变，只有位移在变；单独成层后每帧只更新这一层，
      // 不必把它并入整页的重绘记录。
      bottomNav = RepaintBoundary(child: bottomNav);

      if (_bars.hideBottomBar) {
        if (_bars.offset case final barOffset?) {
          return ValueListenableBuilder(
            valueListenable: barOffset,
            builder: (context, offset, child) => FractionalTranslation(
              translation: Offset(
                0.0,
                offset / Style.topBarHeight,
              ),
              child: child,
            ),
            child: bottomNav,
          );
        }
        if (_bars.showBottom case final showBottomBar?) {
          return ValueListenableBuilder(
            valueListenable: showBottomBar,
            builder: (context, visible, child) => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, visible ? 0 : 1),
              child: child,
            ),
            child: bottomNav,
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _sideBar() {
    if (_navigation.length > 1) {
      if (context.isTablet && _layout.tabletDrawer) {
        return Padding(
          padding: const .only(top: 25),
          child: MediaQuery.removePadding(
            context: context,
            removeRight: true,
            child: DrawerTheme(
              data: DrawerThemeData(width: 130 + _padding.left),
              child: ValueListenableBuilder(
                valueListenable: _selectedIndex,
                builder: (context, index, _) => NavigationDrawer(
                  /// apply `lib/scripts/navigation_drawer.patch`
                  flex: 5,
                  backgroundColor: Colors.transparent,
                  onDestinationSelected: _selectTab,
                  selectedIndex: index,
                  header: Expanded(flex: 4, child: userAndSearchVertical()),
                  tilePadding: const .symmetric(vertical: 5, horizontal: 12),
                  indicatorShape: const RoundedRectangleBorder(
                    borderRadius: .all(.circular(16)),
                  ),
                  children: _navigation
                      .map(
                        (e) => NavigationDrawerDestination(
                          label: Text(e.label),
                          icon: _buildIcon(type: e),
                          selectedIcon: _buildIcon(
                            type: e,
                            selected: true,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }
      return ValueListenableBuilder(
        valueListenable: _selectedIndex,
        builder: (context, index, _) => NavigationRail(
          groupAlignment: 0.5,
          labelType: .selected,
          leading: userAndSearchVertical(),
          backgroundColor: Colors.transparent,
          onDestinationSelected: _selectTab,
          selectedIndex: index,
          destinations: _navigation
              .map(
                (e) => NavigationRailDestination(
                  label: Text(e.label),
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              )
              .toList(),
        ),
      );
    }
    return Container(
      width: 80,
      margin: .only(top: 12 + _padding.top, left: _padding.left),
      child: userAndSearchVertical(),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_tabs case final tabs?) {
      child = TabBarView(
        controller: tabs,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _bars.useBottomNavigation ? .horizontal : .vertical,
        children: [
          for (final (index, tab) in _navigation.indexed)
            TabActivity(
              controller: tabs,
              index: index,
              child: _navigationPage(tab),
            ),
        ],
      );
    } else {
      child = PageView(
        controller: _pages,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final (index, tab) in _navigation.indexed)
            ValueListenableBuilder(
              valueListenable: _selectedIndex,
              builder: (context, selected, child) => TickerMode(
                enabled: selected == index,
                child: child!,
              ),
              child: InactivePaintCleanup(child: _navigationPage(tab)),
            ),
        ],
      );
    }

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_bars.useBottomNavigation) {
      bottomNav = _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: bottomNav,
        );
      }
      padding = _padding.copyWith(bottom: 0);
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(top: _padding.top, right: _padding.right);
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: Padding(padding: padding, child: child),
      ),
    );

    if (PlatformUtils.isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: _colorScheme.brightness,
          statusBarIconBrightness: _colorScheme.brightness.reverse,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: _colorScheme.brightness.reverse,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _navigationPage(NavigationBarType type) => switch (type) {
    .home => HomePage(
      bars: _bars,
      onOpenMine: _openMine,
      register: (actions) {
        _home = actions;
        return () {
          if (identical(_home, actions)) _home = null;
        };
      },
    ),
    .dynamics => DynamicsPage(
      bars: _bars,
      isSelected: () => _selectedTab == .dynamics,
      register: (handle) {
        _dynamics = handle;
        return () {
          if (identical(_dynamics, handle)) _dynamics = null;
        };
      },
    ),
    .mine => MinePage(
      bars: _bars,
      isSelected: () => _selectedTab == .mine,
      showShellActions: !_hasHome,
    ),
  };

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = mainNavigationIcon(type, selected: selected);
    return type == .dynamics
        ? ValueListenableBuilder(
            valueListenable: _badges.dynamicMode,
            builder: (context, mode, _) => ValueListenableBuilder(
              valueListenable: _badges.dynamicCount,
              builder: (context, count, child) => Badge(
                isLabelVisible: mode != .hidden && count > 0,
                label: mode == .number ? Text(count.toString()) : null,
                padding: const .symmetric(horizontal: 6),
                child: child,
              ),
              child: icon,
            ),
          )
        : icon;
  }

  Widget userAndSearchVertical() {
    return Column(
      children: [
        userAvatar(colorScheme: _colorScheme, onOpenMine: _openMine),
        const SizedBox(height: 8),
        const MessageBadge(),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(
            Icons.search_outlined,
            semanticLabel: '搜索',
          ),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
