import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/ranked_video.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/hot_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/pages/rank/view.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HotPage extends ConsumerStatefulWidget {
  const HotPage({
    super.key,
    this.register,
    this.onOpenRank,
    this.bottomBarVisible,
  });

  final VoidCallback Function(DiscoveryPageHandle)? register;
  final bool Function()? onOpenRank;
  final bool Function()? bottomBarVisible;

  @override
  ConsumerState<HotPage> createState() => _HotPageState();
}

class _HotPageState extends ConsumerState<HotPage>
    with AutomaticKeepAliveClientMixin, GridMixin {
  final _owner = Object();
  final _scrollController = ScrollController();
  HotFeed get controller => ref.read(hotFeedProvider(_owner).notifier);
  VoidCallback? _unregister;

  @override
  void initState() {
    super.initState();
    _unregister = widget.register?.call(
      DiscoveryPageHandle(
        () => _scrollController,
        () => controller.onRefresh(),
        readSnapshot: () => ref.read(hotFeedProvider(_owner)),
      ),
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _openRank() {
    if (widget.onOpenRank?.call() == true) return;
    Get.to(
      SimpleScaffold(
        appBar: AppBar(title: const Text('排行榜')),
        body: ViewSafeArea(
          child: RankPage(bottomBarVisible: widget.bottomBarVisible),
        ),
      ),
    );
  }

  Widget _buildEntranceItem({
    required String iconUrl,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        spacing: 4,
        mainAxisSize: MainAxisSize.min,
        children: [
          NetworkImgLayer(
            width: 35,
            height: 35,
            type: .emote,
            src: iconUrl,
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(hotFeedProvider(_owner));
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: FeedPagination(
        // 两行卡片加列表底部留白，窗口缩放后使用最新网格行高。
        prefetchExtent: () =>
            (gridDelegate.layoutCache?.mainAxisStride ?? 0) * 2 + 100,
        controller: _scrollController,
        dataRevision: state,
        dataSource: state.source,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: controller.onLoadMore,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          physics: const AlwaysScrollableScrollPhysics(),
          controller: _scrollController,
          slivers: [
            if (ref.watch(hotEntrancesProvider))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const .only(left: 12, top: 12, right: 12),
                  child: Row(
                    mainAxisAlignment: .spaceEvenly,
                    children: [
                      _buildEntranceItem(
                        iconUrl: 'https://i0.hdslb.com/bfs/archive/a3f11218aaf4521b4967db2ae164ecd3052586b9.png',
                        title: '排行榜',
                        onTap: _openRank,
                      ),
                      _buildEntranceItem(
                        iconUrl: 'https://i0.hdslb.com/bfs/archive/552ebe8c4794aeef30ebd1568b59ad35f15e21ad.png',
                        title: '每周必看',
                        onTap: () => Get.toNamed('/popularSeries'),
                      ),
                      _buildEntranceItem(
                        iconUrl: 'https://i0.hdslb.com/bfs/archive/3693ec9335b78ca57353ac0734f36a46f3d179a9.png',
                        title: '入站必刷',
                        onTap: () => Get.toNamed('/popularPrecious'),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 7, bottom: 100),
              sliver: _buildBody(state.loading),
            ),
            DiscoveryFooter(
              error: state.loading is Success ? state.error : null,
              retry: controller.retry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? InactiveFeedSliver(
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemBuilder: (context, index) {
                    return VideoCardH(
                      videoItem: response[index],
                      onRemove: () => controller.remove(response[index]),
                    );
                  },
                  itemCount: response.length,
                ),
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }
}
