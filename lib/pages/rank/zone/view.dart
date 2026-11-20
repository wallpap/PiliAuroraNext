import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/ranked_video.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/pgc/rank/pgc_rank_item_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/content_discovery/application/rank_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/pages/rank/zone/widget/pgc_rank_item.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_ui/material_ui.dart';

class ZonePage extends ConsumerStatefulWidget {
  const ZonePage({super.key, this.rid, this.seasonType, this.register});

  final VoidCallback Function(ScrollOrRefreshMixin handle)? register;
  final int? rid;
  final int? seasonType;

  @override
  ConsumerState<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends ConsumerState<ZonePage>
    with AutomaticKeepAliveClientMixin, GridMixin {
  final _owner = Object();
  final _scrollController = ScrollController();
  RankQuery get _query =>
      (owner: _owner, rid: widget.rid, seasonType: widget.seasonType);
  RankFeed get controller => ref.read(rankFeedProvider(_query).notifier);
  VoidCallback? _unregister;
  @override
  void initState() {
    super.initState();
    _unregister = widget.register?.call(
      DiscoveryPageHandle(
        () => _scrollController,
        () => controller.onRefresh(),
        readSnapshot: () => ref.read(rankFeedProvider(_query)),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(rankFeedProvider(_query));
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.loading is Success && state.error != null)
            DiscoveryFooter(error: state.error, retry: controller.retry),
          SliverPadding(
            padding: const EdgeInsets.only(top: 7, bottom: 100),
            sliver: _buildBody(state.loading),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LoadingState<List<Object>> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? InactiveFeedSliver(
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemBuilder: (context, index) {
                    final item = response[index];
                    if (item is HotVideoItemModel) {
                      return VideoCardH(
                        videoItem: item,
                        onRemove: () => controller.remove(item),
                      );
                    }
                    return item is PgcRankItemModel
                        ? PgcRankItem(item: item)
                        : const SizedBox.shrink();
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
