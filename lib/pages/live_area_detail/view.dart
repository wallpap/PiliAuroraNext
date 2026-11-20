import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/widgets/image/image_type.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_area.dart';
import 'package:pili_aurora_next/pages/live_area_detail/child/view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';
import 'package:pili_aurora_next/features/content_discovery/application/live_area_feed.dart';
import 'package:pili_aurora_next/pages/live_search/view.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class LiveAreaDetailPage extends ConsumerStatefulWidget {
  const LiveAreaDetailPage({
    super.key,
    required this.areaId,
    required this.parentAreaId,
    required this.parentName,
  });
  final Object? areaId, parentAreaId;
  final String parentName;
  @override
  ConsumerState<LiveAreaDetailPage> createState() => _LiveAreaDetailPageState();
}

class _LiveAreaDetailPageState extends ConsumerState<LiveAreaDetailPage> {
  final _owner = Object();
  bool _showFirstFrame = false;
  LiveDirectoryQuery get _query =>
      (owner: _owner, parentId: widget.parentAreaId);
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveDirectoryProvider(_query));
    final padding = MediaQuery.viewPaddingOf(context);
    final list = state.loading.dataOrNull;
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(widget.parentName),
        actions: [
          IconButton(
            onPressed: () => Get.to(const LiveSearchPage()),
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(left: padding.left, right: padding.right),
        child: state.loading is Loading
            ? const Center(child: CircularProgressIndicator())
            : list != null && list.isNotEmpty
            ? _AreaTabs(
                key: ObjectKey(state.source),
                areas: list,
                areaId: widget.areaId,
                parentName: widget.parentName,
                showFirstFrame: _showFirstFrame,
                onToggleFrame: () =>
                    setState(() => _showFirstFrame = !_showFirstFrame),
              )
            : Column(
                children: [
                  if (state.loading case Error error)
                    TextButton(
                      onPressed: ref
                          .read(liveDirectoryProvider(_query).notifier)
                          .onReload,
                      child: Text('${error.toString()} · 重试分区目录'),
                    ),
                  Expanded(
                    child: LiveAreaChildPage(
                      areaId: widget.areaId,
                      parentAreaId: widget.parentAreaId,
                      showFirstFrame: _showFirstFrame,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tab 与子页滚动资源跟随已确认的目录快照释放。
class _AreaTabs extends StatefulWidget {
  const _AreaTabs({
    super.key,
    required this.areas,
    required this.areaId,
    required this.parentName,
    required this.showFirstFrame,
    required this.onToggleFrame,
  });
  final List<AreaItem> areas;
  final Object? areaId;
  final String parentName;
  final bool showFirstFrame;
  final VoidCallback onToggleFrame;
  @override
  State<_AreaTabs> createState() => _AreaTabsState();
}

class _AreaTabsState extends State<_AreaTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _pages = <int, ScrollOrRefreshMixin>{};
  @override
  void initState() {
    super.initState();
    final selected = widget.areas.indexWhere(
      (area) => area.id?.toString() == widget.areaId?.toString(),
    );
    _tabs = TabController(
      length: widget.areas.length,
      initialIndex: selected < 0 ? 0 : selected,
      vsync: this,
    );
  }

  VoidCallback _register(int index, ScrollOrRefreshMixin handle) {
    _pages[index] = handle;
    return () {
      if (identical(_pages[index], handle)) _pages.remove(index);
    };
  }

  @override
  void dispose() {
    _pages.clear();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                dividerHeight: 0,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                controller: _tabs,
                tabs: widget.areas
                    .map((area) => Tab(text: area.name ?? ''))
                    .toList(),
                onTap: (index) {
                  if (!_tabs.indexIsChanging) _pages[index]?.animateToTop();
                },
              ),
            ),
            iconButton(
              iconSize: 20,
              tooltip: '切换${widget.showFirstFrame ? '封面' : '首帧'}',
              icon: widget.showFirstFrame
                  ? const Icon(MdiIcons.alphaFBox)
                  : const Icon(MdiIcons.image),
              onPressed: widget.onToggleFrame,
            ),
            iconButton(
              iconSize: 20,
              tooltip: '显示菜单',
              icon: const Icon(Icons.menu),
              onPressed: () => _showTags(context, theme, bottom, widget.areas),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: tabBarView(
            controller: _tabs,
            children: [
              for (final (index, area) in widget.areas.indexed)
                TabActivity(
                  controller: _tabs,
                  index: index,
                  child: LiveAreaChildPage(
                    key: ValueKey((area.id, area.parentId)),
                    areaId: area.id,
                    parentAreaId: area.parentId,
                    showFirstFrame: widget.showFirstFrame,
                    register: (handle) => _register(index, handle),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagItem({
    required ThemeData theme,
    required AreaItem item,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NetworkImgLayer(
            width: 45,
            height: 45,
            src: item.pic,
            type: ImageType.emote,
          ),
          const SizedBox(height: 4),
          Text(
            item.name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showTags(
    BuildContext context,
    ThemeData theme,
    double bottom,
    List<AreaItem> list,
  ) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          minChildSize: 0,
          maxChildSize: 1,
          initialChildSize: 1,
          snap: true,
          expand: false,
          snapSizes: const [1],
          builder: (_, scrollController) {
            return Column(
              children: [
                AppBar(
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  title: Text(widget.parentName),
                  actions: [
                    IconButton(
                      onPressed: Get.back,
                      icon: const Icon(Icons.clear),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      top: 12,
                      bottom: bottom + 100,
                    ),
                    itemCount: list.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 100,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 80,
                        ),
                    itemBuilder: (_, index) {
                      return _tagItem(
                        theme: theme,
                        item: list[index],
                        onTap: () {
                          Get.back();
                          if (mounted) _tabs.index = index;
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
