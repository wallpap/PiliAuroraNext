import 'package:pili_aurora_next/common/widgets/flutter/vertical_tabs.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';
import 'package:pili_aurora_next/models/common/rank_type.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/pages/home/controller.dart';
import 'package:pili_aurora_next/pages/rank/zone/view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _pages = <int, ScrollOrRefreshMixin>{};
  final _fallbackScroll = ScrollController();
  VoidCallback? _unregister;
  ScrollOrRefreshMixin? get _current => _pages[_tabs.index];
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: RankType.values.length, vsync: this);
    if (Get.isRegistered<HomeController>()) {
      _unregister = Get.find<HomeController>().registerPage(
        HomeTabType.rank,
        DiscoveryPageHandle(
          () => _current?.scrollController ?? _fallbackScroll,
          () => _current?.onRefresh() ?? Future.value(),
        ),
      );
    }
  }

  VoidCallback _register(int index, ScrollOrRefreshMixin handle) {
    _pages[index] = handle;
    return () {
      if (identical(_pages[index], handle)) _pages.remove(index);
    };
  }

  @override
  void dispose() {
    _unregister?.call();
    _pages.clear();
    _tabs.dispose();
    _fallbackScroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildTab(theme),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabs,
            children: [
              for (final (index, item) in RankType.values.indexed)
                TabActivity(
                  controller: _tabs,
                  index: index,
                  child: ZonePage(
                    rid: item.rid,
                    seasonType: item.seasonType,
                    register: (handle) => _register(index, handle),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(ThemeData theme) {
    return VerticalTabBar(
      dividerWidth: 0,
      isScrollable: true,
      indicatorWeight: 3,
      indicatorSize: .tab,
      controller: _tabs,
      padding: .only(bottom: MediaQuery.paddingOf(context).bottom + 105),
      tabs: RankType.values.map((e) => VerticalTab(text: e.label)).toList(),
      onTap: (index) {
        if (!_tabs.indexIsChanging) {
          _current?.animateToTop();
        } else {
          _tabs.animateTo(index);
        }
      },
    );
  }
}
