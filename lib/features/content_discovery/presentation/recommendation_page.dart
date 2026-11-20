import 'dart:collection';

import 'package:pili_aurora_next/common/skeleton/video_card_v.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_v.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/recommended_video.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_state.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_cover_prefetch.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_viewport.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/image_utils.dart';
import 'package:flutter/rendering.dart'
    show ScrollCacheExtent, SliverGridRegularTileLayout;
import 'package:material_ui/material_ui.dart';

/// 首页壳只持有滚动和刷新意图，不通过句柄修改查询状态。
class RecommendationPageHandle with ScrollOrRefreshMixin {
  RecommendationPageHandle(this.scrollController, this._feed);
  @override
  final ScrollController scrollController;
  final RecommendationFeed Function() _feed;
  RecommendationState get snapshot => _feed().snapshot;
  bool isPending(Object item) => _feed().isPending(item);
  @override
  Future<void> onRefresh() => _feed().onRefresh();
}

class RecommendationPage extends ConsumerStatefulWidget {
  const RecommendationPage({super.key, this.register});
  final VoidCallback Function(RecommendationPageHandle handle)? register;
  @override
  ConsumerState<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends ConsumerState<RecommendationPage>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _viewportOwner = Object();
  RecommendationFeed? _viewportFeed;
  RecommendationFeed get controller =>
      ref.read(recommendationFeedProvider.notifier);
  late final RecommendationPageHandle _handle;
  VoidCallback? _unregister;
  final _coverPrefetch = RecommendationCoverPrefetch(
    (url) => CachedImageProvider(url).prefetchSourceFile(),
  );
  (RecommendationState, int, int)? _coverRow;
  bool _scrollingForward = true;

  @override
  void initState() {
    super.initState();
    _handle = RecommendationPageHandle(_scrollController, () => controller);
    _unregister = widget.register?.call(_handle);
  }

  @override
  void dispose() {
    _viewportFeed?.removeViewport(_viewportOwner);
    _coverPrefetch.clear();
    _unregister?.call();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _reportViewport(int items, int columns, bool active) {
    final feed = controller;
    if (!identical(feed, _viewportFeed)) {
      _viewportFeed?.removeViewport(_viewportOwner);
      _viewportFeed = feed;
    }
    feed.updateViewport(
      owner: _viewportOwner,
      itemCount: items,
      columns: columns,
      active: active,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(recommendationFeedProvider);
    final colorScheme = ColorScheme.of(context);
    final active = TickerMode.valuesOf(context).enabled;
    if (!active) _clearCoverPrefetch();
    return Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: RecommendationViewport(
        cardWidth: ref.watch(recommendationCardWidthProvider),
        onChanged: _reportViewport,
        builder: (gridDelegate, items, layout) {
          void prefetch() {
            if (mounted && active && identical(controller.snapshot, state)) {
              _prefetchCovers(state, layout);
            }
          }

          WidgetsBinding.instance.addPostFrameCallback((_) => prefetch());
          return refreshIndicator(
            onRefresh: controller.onRefresh,
            child: FeedPagination(
              // 两行卡片加列表底部留白，窗口缩放后使用最新网格行高。
              prefetchExtent: () => layout.mainAxisStride * 2 + 100,
              controller: _scrollController,
              dataRevision: state,
              dataSource: state.source,
              canLoadMore: () =>
                  state.canLoadMore &&
                  _scrollController.hasClients &&
                  _scrollController.position.pixels > 0,
              onLoadMore: controller.onLoadMore,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  final delta = notification.scrollDelta ?? 0;
                  if (notification.depth == 0 && delta != 0) {
                    _scrollingForward = delta > 0;
                    prefetch();
                  }
                  return false;
                },
                child: CustomScrollView(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const .only(top: Style.cardSpace),
                      sliver: _buildBody(
                        colorScheme,
                        state,
                        gridDelegate,
                        items,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 100,
                        child:
                            state.loading.dataOrNull?.isNotEmpty == true &&
                                state.error != null
                            ? Center(
                                child: TextButton.icon(
                                  onPressed: controller.retryLoadMore,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('加载失败，点击重试'),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _prefetchCovers(
    RecommendationState state,
    SliverGridRegularTileLayout layout,
  ) {
    final position = _scrollController.positions.singleOrNull;
    final items = state.loading.dataOrNull;
    if (position == null || !position.haveDimensions || items == null) {
      _clearCoverPrefetch();
      return;
    }
    final top = position.pixels - Style.cardSpace;
    final bottom = top + position.viewportDimension;
    final row = _scrollingForward
        ? (bottom / layout.mainAxisStride).ceil()
        : ((top - layout.childMainAxisExtent) / layout.mainAxisStride).floor();
    final key = (state, row, layout.crossAxisCount);
    if (_coverRow == key) return;
    _coverRow = key;
    final history = state.historyStart;
    final start = row * layout.crossAxisCount;
    final urls = <String>[];
    for (var offset = 0; row >= 0 && offset < layout.crossAxisCount; offset++) {
      final slot = start + offset;
      if (slot == history) continue;
      final index = history != null && slot > history ? slot - 1 : slot;
      if (index >= items.length) break;
      final item = items[index];
      if (controller.isPending(item)) continue;
      if (_staticCoverUrl(item.cover) case final url?) urls.add(url);
    }
    _coverPrefetch.update(urls);
  }

  void _clearCoverPrefetch() {
    _coverRow = null;
    _coverPrefetch.clear();
  }

  static final _staticCoverExtension = RegExp(
    r'\.(jpe?g|png)(?:@|$)',
    caseSensitive: false,
  );

  static String? _staticCoverUrl(String? cover) {
    if (cover == null ||
        !_staticCoverExtension.hasMatch(Uri.tryParse(cover)?.path ?? '')) {
      return null;
    }
    return ImageUtils.thumbnailUrl(cover);
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    RecommendationState state,
    SliverGridDelegateWithExtentAndRatio gridDelegate,
    int skeletonItems,
  ) {
    return switch (state.loading) {
      Loading() => _buildSkeleton(gridDelegate, skeletonItems),
      Success(:final response) =>
        response.isNotEmpty
            ? _buildGrid(
                response,
                gridDelegate,
                colorScheme,
                state.historyStart,
              )
            : state.loadingMore
            ? _buildSkeleton(gridDelegate, skeletonItems)
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _buildGrid(
    List<BaseRcmdVideoItemModel> items,
    SliverGridDelegateWithExtentAndRatio gridDelegate,
    ColorScheme colorScheme,
    int? historyStart,
  ) {
    const historyKey = ValueKey('recommendation-history');
    // 仅在列表结构发布时建立索引；卡片揭示不进入这里。
    final indices = HashMap<Object, int>.identity();
    for (var i = 0; i < items.length; i++) {
      indices[items[i]] =
          i + (historyStart != null && i >= historyStart ? 1 : 0);
    }
    return InactiveFeedSliver(
      sliver: SliverGrid.builder(
        gridDelegate: gridDelegate,
        findChildIndexCallback: (key) => key == historyKey
            ? historyStart
            : key is ObjectKey
            ? indices[key.value]
            : null,
        itemCount: items.length + (historyStart != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == historyStart) {
            return GestureDetector(
              key: historyKey,
              onTap: () {
                _handle.animateToTop();
                controller.onRefresh();
              },
              child: Card(
                child: Container(
                  alignment: .center,
                  padding: const .symmetric(horizontal: 10),
                  child: Text(
                    '上次看到这里\n点击刷新',
                    textAlign: .center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            );
          }
          final actualIndex = historyStart != null && index > historyStart
              ? index - 1
              : index;
          final item = items[actualIndex];
          return _RecommendationCard(
            key: ObjectKey(item),
            item: item,
          );
        },
      ),
    );
  }

  Widget _buildSkeleton(
    SliverGridDelegateWithExtentAndRatio delegate,
    int items,
  ) => SliverGrid(
    gridDelegate: delegate,
    delegate: SliverSingleChildDelegate(
      count: items,
      child: const VideoCardVSkeleton(),
    ),
  );
}

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard({super.key, required this.item});
  final BaseRcmdVideoItemModel item;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(recommendationCardPendingProvider(item))
      ? const VideoCardVSkeleton()
      : VideoCardV(
          videoItem: item,
          onRemove: () => ref
              .read(recommendationFeedProvider.notifier)
              .removeRecommendation(item),
        );
}
