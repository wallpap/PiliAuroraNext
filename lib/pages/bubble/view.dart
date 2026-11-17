import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/list_tile.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/community/application/bubble_feed.dart';
import 'package:pili_aurora_next/features/community/domain/bubble_catalog.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/bubble/dyn_list.dart';
import 'package:pili_aurora_next/utils/extension/scroll_controller_ext.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart'
    hide ListTile, SliverGridDelegateWithMaxCrossAxisExtent;

class BubblePage extends ConsumerStatefulWidget {
  const BubblePage({super.key, required this.tribeId, this.categoryId});
  final String tribeId;
  final String? categoryId;
  @override
  ConsumerState<BubblePage> createState() => _BubblePageState();
}

class _BubblePageState extends ConsumerState<BubblePage>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  int? _sort;
  BubbleQuery get _query => (
    owner: _owner,
    tribeId: widget.tribeId,
    categoryId: widget.categoryId,
    sortType: _sort,
  );
  @override
  bool get wantKeepAlive => widget.categoryId != null;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(bubbleFeedProvider(_query));
    final catalog = state.metadata;
    final child = _BubbleListing(query: _query);
    if (widget.categoryId != null) return child;
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(catalog?.title == null ? '小站' : '${catalog!.title}小站'),
      ),
      body: Padding(
        padding: EdgeInsets.only(
          left: MediaQuery.viewPaddingOf(context).left,
          right: MediaQuery.viewPaddingOf(context).right,
        ),
        child: catalog == null || catalog.categories.isEmpty
            ? child
            : _BubbleTabs(
                key: ObjectKey(catalog),
                query: _query,
                catalog: catalog,
                child: child,
              ),
      ),
      fab: catalog?.sort?.showSort != true
          ? null
          : FloatingActionButton.extended(
              tooltip: '排序',
              icon: const Icon(Icons.sort, size: 20),
              label: const Text('排序'),
              onPressed: () async {
                final source = state.source;
                final selected = await showDialog<int>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    children: [
                      for (final item in catalog!.sort!.sortItems ?? [])
                        ListTile(
                          title: Text(item.text ?? ''),
                          selected: item.sortType == catalog.sort!.curSortType,
                          onTap: () => Navigator.of(context).pop(item.sortType),
                        ),
                    ],
                  ),
                );
                if (!mounted ||
                    selected == null ||
                    !identical(
                      ref.read(bubbleFeedProvider(_query)).source,
                      source,
                    )) {
                  return;
                }
                setState(() => _sort = selected);
              },
            ),
    );
  }
}

class _BubbleTabs extends StatefulWidget {
  const _BubbleTabs({
    super.key,
    required this.query,
    required this.catalog,
    required this.child,
  });
  final BubbleQuery query;
  final BubbleCatalog catalog;
  final Widget child;
  @override
  State<_BubbleTabs> createState() => _BubbleTabsState();
}

class _BubbleTabsState extends State<_BubbleTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: widget.catalog.categories.length,
    vsync: this,
  );
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: .start,
        tabs: [
          for (final category in widget.catalog.categories)
            Tab(text: category.name ?? ''),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            widget.child,
            for (final category in widget.catalog.categories.skip(1))
              _BubbleListing(
                key: ValueKey(category.id),
                query: (
                  owner: widget.query.owner,
                  tribeId: widget.query.tribeId,
                  categoryId: category.id,
                  sortType: widget.query.sortType,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _BubbleListing extends ConsumerStatefulWidget {
  const _BubbleListing({super.key, required this.query});
  final BubbleQuery query;
  @override
  ConsumerState<_BubbleListing> createState() => _BubbleListingState();
}

class _BubbleListingState extends ConsumerState<_BubbleListing>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  BubbleFeed get controller =>
      ref.read(bubbleFeedProvider(widget.query).notifier);
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(bubbleFeedProvider(widget.query));
    ref.listen(
      bubbleFeedProvider(widget.query).select((value) => value.source),
      (_, _) => _scroll.jumpToTop(),
    );
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: FeedPagination(
        controller: _scroll,
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: controller.onLoadMore,
        prefetchExtent: () => 300,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              sliver: _body(state.loading),
            ),
            DiscoveryFooter(error: state.error, retry: controller.retry),
          ],
        ),
      ),
    );
  }

  Widget _body(LoadingState<List<DynList>> loading) => switch (loading) {
    Loading() => const SliverFillRemaining(child: m3eLoading),
    Error(:final errMsg) => HttpError(
      errMsg: errMsg,
      onReload: controller.onReload,
    ),
    Success(:final response) =>
      response.isEmpty
          ? HttpError(onReload: controller.onReload)
          : SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                mainAxisExtent: 56,
                maxCrossAxisExtent: 2 * Grid.smallCardWidth,
              ),
              itemCount: response.length,
              itemBuilder: (context, index) {
                final item = response[index];
                return Material(
                  type: .transparency,
                  child: ListTile(
                    safeArea: false,
                    visualDensity: .standard,
                    onTap: () => Get.toNamed(
                      '/articlePage',
                      parameters: {'id': item.dynId ?? '', 'type': 'opus'},
                    ),
                    title: Text(
                      item.title ?? '',
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                    trailing: item.meta?.timeText == null
                        ? null
                        : Text(
                            item.meta!.timeText!,
                            style: const TextStyle(fontSize: 13),
                          ),
                  ),
                );
              },
            ),
  };
}
