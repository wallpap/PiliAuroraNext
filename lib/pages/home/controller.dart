import 'dart:async';
import 'dart:math';

import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/pages/live/controller.dart';
import 'package:pili_aurora_next/pages/rank/controller.dart';
import 'package:pili_aurora_next/pages/pgc/controller.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/pages/common/common_controller.dart';
import 'package:pili_aurora_next/pages/main/controller.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/wbi_sign.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin {
  late List<HomeTabType> tabs;
  late TabController tabController;
  late final VoidCallback _unregisterPageDiagnostics;
  int? _lastDiagnosticTab;

  RxBool? showTopBar;
  late final bool hideTopBar;

  bool enableSearchWord = Pref.enableSearchWord;
  late final RxString defaultSearch = ''.obs;
  late int lateCheckSearchAt = 0;

  final _pages = <HomeTabType, ScrollOrRefreshMixin>{};
  ScrollOrRefreshMixin? registeredPage(HomeTabType type) => _pages[type];
  VoidCallback registerPage(HomeTabType type, ScrollOrRefreshMixin handle) {
    _pages[type] = handle;
    return () {
      if (identical(_pages[type], handle)) _pages.remove(type);
    };
  }

  ScrollOrRefreshMixin get controller {
    final type = tabs[tabController.index];
    return _pages[type] ??
        switch (type) {
          HomeTabType.rcmd => throw StateError('推荐页尚未挂载'),
          HomeTabType.live => Get.find<LiveController>(),
          HomeTabType.hot => throw StateError('热门页尚未挂载'),
          HomeTabType.rank => Get.find<RankController>(),
          HomeTabType.bangumi ||
          HomeTabType.cinema => Get.find<PgcController>(tag: type.name),
        };
  }

  @override
  ScrollController get scrollController => controller.scrollController;

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

    if (enableSearchWord) {
      lateCheckSearchAt = DateTime.now().millisecondsSinceEpoch;
      querySearchDefault();
    }

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
    // 标签切换早于目标页面创建时，控制器尚未注册。
    try {
      final active = controller;
      if (active is RecommendationPageHandle) {
        final snapshot = active.snapshot;
        result['requestPending'] = snapshot.loadingMore;
        result['state'] = switch (snapshot.loading) {
          Loading() => 'loading',
          Success() => 'success',
          Error() => 'error',
        };
        result['items'] = snapshot.loading.dataOrNull?.length ?? 0;
      } else if (active is CommonController) {
        result['requestPending'] = active.isLoading;
        result['state'] = switch (active.loadingState.value) {
          Loading() => 'loading',
          Success() => 'success',
          Error() => 'error',
        };
        final data = active.loadingState.value.dataOrNull;
        if (data is List) result['items'] = data.length;
      }
    } catch (_) {
      result['controllerReady'] = false;
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

  @override
  Future<void> onRefresh() {
    return controller.onRefresh().catchError((Object e, StackTrace stackTrace) {
      logger.w('刷新首页失败', error: e, stackTrace: stackTrace);
    });
  }

  void setTabConfig() {
    final tabs = GStorage.setting.get(SettingBoxKey.tabBarSort) as List?;
    if (tabs != null) {
      this.tabs = tabs.map((i) => HomeTabType.values[i]).toList();
    } else {
      this.tabs = HomeTabType.values;
    }

    tabController = TabController(
      initialIndex: max(0, this.tabs.indexOf(HomeTabType.rcmd)),
      length: this.tabs.length,
      vsync: this,
    );
  }

  @override
  void onClose() {
    _pages.clear();
    _unregisterPageDiagnostics();
    tabController.dispose();
    super.onClose();
  }

  Future<void> querySearchDefault() async {
    try {
      final res = await Request().get(
        Api.searchDefault,
        queryParameters: await WbiSign.makSign({'web_location': 333.1365}),
      );
      if (res.data['code'] == 0) {
        defaultSearch.value = res.data['data']?['name'] ?? '';
        // defaultSearch.value = res.data['data']?['show_name'] ?? '';
      }
    } catch (_) {}
  }
}
