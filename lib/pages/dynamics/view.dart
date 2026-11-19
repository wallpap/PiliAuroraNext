import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamics_type.dart';
import 'package:pili_aurora_next/models/common/dynamic/up_panel_position.dart';
import 'package:pili_aurora_next/models/dynamics/up.dart';
import 'package:pili_aurora_next/pages/common/common_page.dart';
import 'package:pili_aurora_next/features/app_shell/application/shell_badges.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/scroll_bars.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_authors.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/up_panel.dart';
import 'package:pili_aurora_next/pages/dynamics_create/view.dart';
import 'package:pili_aurora_next/pages/dynamics_tab/view.dart';
import 'package:pili_aurora_next/utils/extension/scroll_controller_ext.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key, this.bars, this.isSelected, this.register});

  final ShellScrollBars? bars;
  final bool Function()? isSelected;
  final VoidCallback Function(DiscoveryPageHandle)? register;

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final _owner = Object();
  final _scroll = ScrollController();
  late TabController _tabs;
  late UpPanelPosition upPanelPosition;
  final _children = <DynamicsTabType, DiscoveryPageHandle>{};
  VoidCallback? _unregister;
  @override
  ShellScrollBars? get scrollBars => widget.bars;
  @override
  bool get respondsToScroll => widget.isSelected?.call() ?? true;
  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);
  DynamicsAuthors get _authors =>
      _container.read(dynamicsAuthorsProvider(_owner).notifier);
  DiscoveryPageHandle? get _active =>
      _children[DynamicsTabType.values[_tabs.index]];
  @override
  void initState() {
    super.initState();
    final preferences = _container.read(dynamicsPreferencesProvider);
    upPanelPosition = preferences.position;
    _tabs = TabController(
      vsync: this,
      length: DynamicsTabType.values.length,
      initialIndex: preferences.initialTab.clamp(
        0,
        DynamicsTabType.values.length - 1,
      ),
    );
    _unregister = widget.register?.call(
      DiscoveryPageHandle(
        () => _active?.scrollController ?? _scroll,
        _refresh,
      ),
    );
  }

  Future<void> _refresh() => Future.wait([
    _authors.onRefresh(),
    if (_active != null) _active!.onRefresh(),
  ]);
  VoidCallback _register(DynamicsTabType type, DiscoveryPageHandle handle) {
    _children[type] = handle;
    return () {
      if (identical(_children[type], handle)) _children.remove(type);
    };
  }

  void _select(int mid) {
    final selection = _container.read(dynamicsSelectionProvider);
    final same = selection.mid == mid;
    _container.read(dynamicsSelectionProvider.notifier).select(mid);
    _authors.markRead(mid);
    _tabs.index = mid == -1 ? 0 : 4;
    if (same) {
      if (mid == -1) _authors.onRefresh();
      _active?.scrollController.jumpToTop();
      _active?.onRefresh();
    }
  }

  @override
  void dispose() {
    _unregister?.call();
    _children.clear();
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Widget _createDynamicBtn(ColorScheme colorScheme, {bool isRight = true}) =>
      Container(
        width: 34,
        height: 34,
        margin: isRight ? const .only(right: 16) : const .only(left: 16),
        child: IconButton(
          tooltip: '发布动态',
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: WidgetStatePropertyAll(
              colorScheme.secondaryContainer,
            ),
          ),
          onPressed: () => CreateDynPanel.onCreateDyn(context),
          icon: Icon(
            Icons.add,
            size: 18,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(dynamicsAuthorsProvider(_owner));
            return FeedPagination(
              controller: _scroll,
              dataSource: state.source,
              dataRevision: state,
              canLoadMore: () => state.canLoadMore,
              onLoadMore: _authors.onLoadMore,
              prefetchExtent: () => 300,
              child: Column(
                children: [
                  if (state.error != null)
                    IconButton(
                      tooltip: state.error.toString(),
                      onPressed: _authors.retry,
                      icon: const Icon(Icons.refresh),
                    ),
                  Expanded(child: _buildUpPanel(state.loading)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        scrollController: _scroll,
        position: upPanelPosition,
        onSelect: _select,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _authors.retry,
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer(
      builder: (context, ref, _) {
        return _buildPage(context);
      },
    );
  }

  Widget _buildPage(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    Widget child = tabBarView(
      controller: _tabs,
      children: DynamicsTabType.values
          .map(
            (e) => DynamicsTabPage(
              dynamicsType: e,
              onRegister: (handle) => _register(e, handle),
              onRefreshAuthors: _authors.onRefresh,
              onRefreshFeed: e == DynamicsTabType.all ? _clearUnread : null,
            ),
          )
          .toList(),
    );

    switch (upPanelPosition) {
      case .top:
        child = Column(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftFixed:
        child = Row(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(colorScheme),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        actions = _createDynamicBtn(colorScheme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createDynamicBtn(colorScheme, isRight: false);
        actions = const EndDrawerButton();
    }

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const .fromHeight(50),
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: TabBar(
                dividerHeight: 0,
                isScrollable: true,
                tabAlignment: .start,
                dividerColor: Colors.transparent,
                labelColor: colorScheme.primary,
                indicatorColor: colorScheme.primary,
                controller: _tabs,
                unselectedLabelColor: colorScheme.onSurface,
                labelStyle:
                    TabBarTheme.of(context).labelStyle
                        ?.copyWith(fontSize: 13) ??
                    const TextStyle(fontSize: 13),
                tabs: DynamicsTabType.values
                    .map((e) => Tab(text: e.label))
                    .toList(),
                onTap: (index) {
                  if (!_tabs.indexIsChanging) {
                    _active?.animateToTop();
                    _scroll.animToTop();
                  }
                },
              ),
            ),
            actions,
          ],
        ),
      ),
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }

  void _clearUnread() => _container.read(shellBadgesProvider).clearDynamics();
}
