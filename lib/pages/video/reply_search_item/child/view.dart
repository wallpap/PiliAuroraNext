import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/community/application/comments/reply_search.dart';
import 'package:pili_aurora_next/features/community/domain/reply_search.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/video/reply_search_item/child/widgets/item.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:material_ui/material_ui.dart';

class ReplySearchChildPage extends ConsumerStatefulWidget {
  const ReplySearchChildPage({
    super.key,
    required this.query,
    required this.scroll,
  });

  final ReplySearchQuery query;
  final ScrollController scroll;

  @override
  ConsumerState<ReplySearchChildPage> createState() =>
      _ReplySearchChildPageState();
}

class _ReplySearchChildPageState extends ConsumerState<ReplySearchChildPage>
    with AutomaticKeepAliveClientMixin, GridMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = replySearchProvider(widget.query);
    final state = ref.watch(provider);
    final query = ref.read(provider.notifier);
    final retry = state.error == null ? query.onReload : query.retry;
    return refreshIndicator(
      onRefresh: query.onRefresh,
      child: FeedPagination(
        controller: widget.scroll,
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: query.onLoadMore,
        child: CustomScrollView(
          controller: widget.scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 7),
              sliver: _buildBody(state.loading, state.error, retry),
            ),
            if (state.error != null &&
                state.loading.dataOrNull?.isNotEmpty == true)
              DiscoveryFooter(error: state.error, retry: query.retry),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    LoadingState<List<ReplySearchEntry>> loadingState,
    Error? pageError,
    Future<void> Function() retry,
  ) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) =>
                    ReplySearchItem(item: response[index]),
                itemCount: response.length,
              )
            : HttpError(errMsg: pageError?.toString(), onReload: retry),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: retry,
      ),
    };
  }

  @override
  bool get wantKeepAlive => true;
}
