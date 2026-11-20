import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';

class LibraryFeedView<T, M> extends StatefulWidget {
  const LibraryFeedView({
    super.key,
    required this.value,
    required this.feed,
    required this.itemBuilder,
  });
  final AsyncValue<FeedState<T, M>> value;
  final PagedFeed<T, M> feed;
  final Widget Function(BuildContext, T, int) itemBuilder;
  @override
  State<LibraryFeedView<T, M>> createState() => _LibraryFeedViewState<T, M>();
}

class _LibraryFeedViewState<T, M> extends State<LibraryFeedView<T, M>>
    with AutomaticKeepAliveClientMixin, GridMixin {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
  Future<void> _refresh() async {
    try {
      await widget.feed.refresh();
    } catch (_) {
      // 查询状态持有错误，按钮和下拉入口均消费同一个失败 Future。
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final value = widget.value;
    final data = widget.feed.displayState;
    return FeedPagination(
      controller: _scroll,
      dataSource: data?.source,
      dataRevision: data,
      canLoadMore: () =>
          !value.isLoading && !value.hasError && (data?.canLoadMore ?? false),
      onLoadMore: () => widget.feed.loadMore(retry: false),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (data == null && value.isLoading)
              gridSkeleton
            else if (data == null && value.hasError)
              HttpError(
                errMsg: value.error.toString(),
                onReload: _refresh,
              )
            else if (data == null || data.items.isEmpty)
              HttpError(onReload: _refresh)
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 7),
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemCount: data.items.length,
                  itemBuilder: (context, index) =>
                      widget.itemBuilder(context, data.items[index], index),
                ),
              ),
            if (data != null && value.hasError)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: _refresh,
                  child: Text('${value.error}，点击重试'),
                ),
              )
            else if (!value.isLoading && data?.loadingMore == true)
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
              )
            else if (data?.error case final error?)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () => widget.feed.loadMore(retry: true),
                  child: Text('$error，点击重试'),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.viewPaddingOf(context).bottom + 85,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
