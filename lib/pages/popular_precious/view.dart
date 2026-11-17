import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/content_discovery/application/curated_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:material_ui/material_ui.dart';

class PopularPreciousPage extends ConsumerStatefulWidget {
  const PopularPreciousPage({super.key});

  @override
  ConsumerState<PopularPreciousPage> createState() =>
      _PopularPreciousPageState();
}

class _PopularPreciousPageState extends ConsumerState<PopularPreciousPage>
    with GridMixin {
  final _owner = Object();
  final _scrollController = ScrollController();
  PreciousFeed get _controller =>
      ref.read(preciousFeedProvider(_owner).notifier);
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(preciousFeedProvider(_owner));
    return SimpleScaffold(
      appBar: AppBar(title: const Text('入站必刷')),
      body: refreshIndicator(
        onRefresh: _controller.onRefresh,
        child: FeedPagination(
          controller: _scrollController,
          dataSource: state.source,
          dataRevision: state,
          canLoadMore: () => state.canLoadMore,
          onLoadMore: _controller.onLoadMore,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ViewSliverSafeArea(
                sliver: _buildBody(state.loading),
              ),
              DiscoveryFooter(
                error: state.loading is Success ? state.error : null,
                retry: _controller.retry,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>> value) {
    switch (value) {
      case Loading():
        return gridSkeleton;
      case Success<List<HotVideoItemModel>>(:final response):
        return SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemCount: response.length,
          itemBuilder: (context, index) {
            final item = response[index];
            return VideoCardH(
              videoItem: item,
              onTap: () {
                PageUtils.toVideoPage(
                  bvid: item.bvid,
                  cid: item.cid!,
                  dimension: item.dimension,
                  extraArguments: {
                    'sourceType': SourceType.playlist,
                    'favTitle': '入站必刷',
                    'mediaId': ref
                        .read(preciousFeedProvider(_owner))
                        .metadata
                        ?.mediaId,
                    'desc': true,
                    'oid': item.aid,
                    'isContinuePlaying': index != 0,
                  },
                );
              },
            );
          },
        );
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _controller.onReload,
        );
    }
  }
}
