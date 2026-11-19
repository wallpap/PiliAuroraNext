import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/shell_actions.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/scroll_bars.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/features/search/application/search_hint.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/mine/view.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/settings/navigation_preferences.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/custom_height_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/pages/common/common_page.dart';
import 'package:pili_aurora_next/pages/hot/view.dart';
import 'package:pili_aurora_next/pages/live/view.dart';
import 'package:pili_aurora_next/pages/pgc/view.dart';
import 'package:pili_aurora_next/pages/rank/view.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

typedef HomePageActions = ({
  VoidCallback toTopOrRefresh,
  Future<void> Function() refresh,
});

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.bars,
    this.onOpenMine,
    this.register,
  });

  final ShellScrollBars? bars;
  final VoidCallback? onOpenMine;
  final VoidCallback Function(HomePageActions)? register;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late ColorScheme _colorScheme;
  late final List<HomeTabType> _tabs;
  late final TabController _tabController;
  late final _layout = NavigationLayoutPreferences();
  ShellScrollBars? _localBars;
  final _pages = <HomeTabType, ScrollOrRefreshMixin>{};
  VoidCallback? _unregister, _unregisterDiagnostics;
  int? _lastDiagnosticTab;
  ScrollOrRefreshMixin? get _active => _pages[_tabs[_tabController.index]];

  @override
  ShellScrollBars get scrollBars => widget.bars ?? _localBars!;

  @override
  bool get needsCorrection => scrollBars.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.bars == null) {
      _localBars = ShellScrollBars(
        hideInstantly: _layout.hideInstantly,
        hideTopBar: !_layout.forceSideBar && _layout.hideTopBar,
        hideBottomBar: false,
      );
    }
    final (:tabs, :index) = NavigationPreferences.readHome();
    _tabs = tabs;
    _tabController = TabController(
      initialIndex: index,
      length: tabs.length,
      vsync: this,
    );
    if (widget.register case final register?) {
      _unregister = register((
        toTopOrRefresh: () => _active?.toTopOrRefresh(),
        refresh: () async => _active?.onRefresh(),
      ));
      _unregisterDiagnostics = Diagnostics.instance.register(
        'homePage',
        _capturePage,
      );
      _tabController.addListener(_recordTabChange);
    }
  }

  VoidCallback _register(HomeTabType type, ScrollOrRefreshMixin handle) {
    _pages[type] = handle;
    return () {
      if (identical(_pages[type], handle)) _pages.remove(type);
    };
  }

  Map<String, Object?> _capturePage() {
    final active = _active;
    final status = switch (active) {
      RecommendationPageHandle(:final snapshot) => (
        snapshot.loading,
        snapshot.loadingMore,
      ),
      DiscoveryPageHandle(snapshot: final snapshot?) => (
        snapshot.loading,
        snapshot.loadingMore,
      ),
      _ => null,
    };
    return {
      'tab': _tabs[_tabController.index].name,
      'transitioning': _tabController.indexIsChanging,
      if (active == null) 'controllerReady': false,
      if (status case (final loading, final pending)) ...{
        'requestPending': pending,
        'state': switch (loading) {
          Loading() => 'loading',
          Success() => 'success',
          Error() => 'error',
        },
        'items': loading.dataOrNull?.length ?? 0,
      },
    };
  }

  void _recordTabChange() {
    final index = _tabController.index;
    if (_lastDiagnosticTab == index) return;
    _lastDiagnosticTab = index;
    Diagnostics.instance.log(
      DiagnosticLogLevel.debug,
      'pageSwitch',
      '切换首页标签',
      details: {'tab': _tabs[index].name},
    );
  }

  ScrollOrRefreshMixin? registeredPage(HomeTabType tab) => _pages[tab];

  bool showTab(HomeTabType tab) {
    if (!mounted) return false;
    final index = _tabs.indexOf(tab);
    if (index < 0) return false;
    if (_tabController.index != index) _tabController.animateTo(index);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
    if (_localBars case final bars?) {
      bars.useBottomNavigation =
          !_layout.forceSideBar && MediaQuery.sizeOf(context).isPortrait;
    }
  }

  @override
  void dispose() {
    _unregister?.call();
    _unregisterDiagnostics?.call();
    _pages.clear();
    _tabController.dispose();
    _localBars?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget tabBar;
    if (_tabs.length > 1) {
      tabBar = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _tabController,
            tabs: _tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: (_) {
              feedBack();
              if (!_tabController.indexIsChanging) {
                _active?.animateToTop();
              }
            },
          ),
        ),
      );
      if (scrollBars.showTop != null) {
        tabBar = Material(
          color: _colorScheme.surface,
          child: tabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return Column(
      children: [
        if (scrollBars.useBottomNavigation) customAppBar(),
        tabBar,
        Expanded(
          child: onBuild(
            tabBarView(
              controller: _tabController,
              children: [
                for (final (index, tab) in _tabs.indexed)
                  TabActivity(
                    controller: _tabController,
                    index: index,
                    child: switch (tab) {
                      .live => LivePage(
                        register: (handle) => _register(tab, handle),
                      ),
                      .rcmd => RecommendationPage(
                        register: (handle) => _register(tab, handle),
                      ),
                      .hot => HotPage(
                        register: (handle) => _register(tab, handle),
                        onOpenRank: () => showTab(.rank),
                        bottomBarVisible: () => scrollBars.bottomVisible,
                      ),
                      .rank => RankPage(
                        register: (handle) => _register(tab, handle),
                        bottomBarVisible: () => scrollBars.bottomVisible,
                      ),
                      .bangumi || .cinema => PgcPage(
                        key: ValueKey(tab),
                        tabType: tab,
                        register: (handle) => _register(tab, handle),
                      ),
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        const MessageBadge(),
        const SizedBox(width: 8),
        userAvatar(
          colorScheme: _colorScheme,
          onOpenMine: widget.onOpenMine ?? openMinePage,
        ),
      ],
    );
    if (scrollBars.hideTopBar) {
      if (scrollBars.offset case final barOffset?) {
        return ValueListenableBuilder(
          valueListenable: barOffset,
          builder: (context, offset, child) => CustomHeightWidget(
            offset: Offset(0, -offset),
            height: Style.topBarHeight - offset,
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
          child: child,
        );
      }
      if (scrollBars.showTop case final showTopBar?) {
        return ValueListenableBuilder(
          valueListenable: showTopBar,
          builder: (context, showSearchBar, child) => AnimatedOpacity(
            opacity: showSearchBar ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: showSearchBar ? Style.topBarHeight : 0,
              padding: padding,
              child: child,
            ),
          ),
          child: child,
        );
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: Consumer(
        builder: (context, ref, _) {
          final hint = ref.watch(searchHintProvider);
          return SizedBox(
            height: 44,
            child: Material(
              borderRadius: borderRadius,
              color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
              child: InkWell(
                borderRadius: borderRadius,
                splashColor: _colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                onTap: () => Get.toNamed(
                  '/search',
                  parameters: hint.enabled
                      ? {'hintText': hint.text.value}
                      : null,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_outlined,
                      color: _colorScheme.onSecondaryContainer,
                      semanticLabel: '搜索',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: hint.text,
                        builder: (context, text, _) => Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
