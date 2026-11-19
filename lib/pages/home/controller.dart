import 'dart:async';

import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';

import 'package:pili_aurora_next/features/search/application/search_hint.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/pages/main/controller.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/settings/navigation_preferences.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late List<HomeTabType> tabs;
  late TabController tabController;
  late final VoidCallback _unregisterPageDiagnostics;
  int? _lastDiagnosticTab;

  RxBool? showTopBar;
  late final bool hideTopBar;

  late final SearchHint searchHint;

  final _pages = <HomeTabType, ScrollOrRefreshMixin>{};
  ScrollOrRefreshMixin? registeredPage(HomeTabType type) => _pages[type];
  VoidCallback registerPage(HomeTabType type, ScrollOrRefreshMixin handle) {
    _pages[type] = handle;
    return () {
      if (identical(_pages[type], handle)) _pages.remove(type);
    };
  }

  ScrollOrRefreshMixin? get _activePage => _pages[tabs[tabController.index]];

  void animateToTop() => _activePage?.animateToTop();
  void toTopOrRefresh() => _activePage?.toTopOrRefresh();

  @override
  void onInit() {
    super.onInit();

    hideTopBar = !Pref.useSideBar && Pref.hideTopBar;
    if (hideTopBar) {
      final mainCtr = Get.find<MainController>();
      switch (mainCtr.barHideType) {
        case .instant:
          showTopBar = RxBool(true);
        case .sync:
          mainCtr.barOffset ??= RxDouble(0.0);
      }
    }

    searchHint = SearchHint();

    setTabConfig();
    _unregisterPageDiagnostics = Diagnostics.instance.register(
      'homePage',
      _capturePage,
    );
    tabController.addListener(_recordTabChange);
  }

  Map<String, Object?> _capturePage() {
    final result = <String, Object?>{
      'tab': tabs[tabController.index].name,
      'transitioning': tabController.indexIsChanging,
    };
    final active = _activePage;
    if (active == null) {
      result['controllerReady'] = false;
    }
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
    if (status case (final loading, final pending)) {
      result['requestPending'] = pending;
      result['state'] = switch (loading) {
        Loading() => 'loading',
        Success() => 'success',
        Error() => 'error',
      };
      result['items'] = loading.dataOrNull?.length ?? 0;
    }
    return result;
  }

  void _recordTabChange() {
    final index = tabController.index;
    if (_lastDiagnosticTab == index) return;
    _lastDiagnosticTab = index;
    Diagnostics.instance.log(
      DiagnosticLogLevel.debug,
      'pageSwitch',
      '切换首页标签',
      details: {'tab': tabs[index].name},
    );
  }

  Future<void> onRefresh() async {
    try {
      await _activePage?.onRefresh();
    } catch (error, stackTrace) {
      logger.w('刷新首页失败', error: error, stackTrace: stackTrace);
    }
  }

  void setTabConfig() {
    final (:tabs, :index) = NavigationPreferences.readHome();
    this.tabs = tabs;
    tabController = TabController(
      initialIndex: index,
      length: tabs.length,
      vsync: this,
    );
  }

  @override
  void onClose() {
    _pages.clear();
    _unregisterPageDiagnostics();
    tabController.dispose();
    searchHint.dispose();
    super.onClose();
  }
}
