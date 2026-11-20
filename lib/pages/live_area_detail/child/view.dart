import 'package:pili_aurora_next/common/skeleton/video_card_v.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/self_sized_horizontal_list.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live/feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live/second_list/tag.dart';
import 'package:pili_aurora_next/pages/live/widgets/live_item_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/content_discovery/application/live_area_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:material_ui/material_ui.dart';

class LiveAreaChildPage extends ConsumerStatefulWidget {
  const LiveAreaChildPage({
    super.key,
    required this.areaId,
    required this.parentAreaId,
    required this.showFirstFrame,
    this.register,
  });

  final Object? areaId;
  final Object? parentAreaId;
  final bool showFirstFrame;
  final VoidCallback Function(ScrollOrRefreshMixin handle)? register;

  @override
  ConsumerState<LiveAreaChildPage> createState() => _LiveAreaChildPageState();
}

class _LiveAreaChildPageState extends ConsumerState<LiveAreaChildPage>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  final _scroll = ScrollController();
  String? _sortType;
  LiveAreaQuery get _query => (
    owner: _owner,
    areaId: widget.areaId,
    parentAreaId: widget.parentAreaId,
    sortType: _sortType,
  );
  LiveAreaFeed get _controller =>
      ref.read(liveAreaFeedProvider(_query).notifier);
  List<LiveSecondTag>? get _tags =>
      ref.read(liveAreaFeedProvider(_query)).metadata?.tags;
  VoidCallback? _unregister;
  @override
  void initState() {
    super.initState();
    _unregister = widget.register?.call(
      DiscoveryPageHandle(
        () => _scroll,
        () => _controller.onRefresh(),
      ),
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    _scroll.dispose();
    super.dispose();
  }

  void _selectTag(int index, String? sortType) {
    if (_sortType == sortType) return;
    setState(() => _sortType = sortType);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(liveAreaFeedProvider(_query));
    final ThemeData theme = Theme.of(context);
    return refreshIndicator(
      onRefresh: _controller.onRefresh,
      child: FeedPagination(
        controller: _scroll,
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: _controller.onLoadMore,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: Style.safeSpace,
                right: Style.safeSpace,
                top: Style.safeSpace,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              sliver: _buildBody(theme, state.loading),
            ),
            DiscoveryFooter(
              error: state.loading is Success ? state.error : null,
              retry: _controller.retry,
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<CardLiveItem>> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => SliverGrid(
        gridDelegate: gridDelegate,
        delegate: const SliverSingleChildDelegate(
          count: 10,
          child: VideoCardVSkeleton(),
        ),
      ),
      Success(:final response) => SliverMainAxisGroup(
        slivers: [
          if (_tags?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  final selected =
                      _tags?.indexWhere((item) => item.sortType == _sortType) ??
                      0;
                  final tagIndex = selected < 0 ? 0 : selected;
                  return SelfSizedHorizontalList(
                    padding: const .only(bottom: 12),
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = _tags![index];
                      final isCurr = index == tagIndex;
                      return SearchText(
                        fontSize: 14,
                        padding: const .symmetric(horizontal: 8, vertical: 3),
                        text: item.name!,
                        bgColor: isCurr
                            ? theme.colorScheme.secondaryContainer
                            : Colors.transparent,
                        textColor: isCurr
                            ? theme.colorScheme.onSecondaryContainer
                            : null,
                        onTap: (value) => _selectTag(index, item.sortType),
                      );
                    },
                    itemCount: _tags!.length,
                  );
                },
              ),
            ),
          response.isNotEmpty
              ? SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemBuilder: (context, index) {
                    return LiveCardVApp(
                      item: response[index],
                      showFirstFrame: widget.showFirstFrame,
                    );
                  },
                  itemCount: response.length,
                )
              : HttpError(onReload: _controller.onReload),
        ],
      ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  @override
  bool get wantKeepAlive => true;
}
