import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/utils/grid.dart';

class LibraryFeedView<T, M> extends StatefulWidget {
  const LibraryFeedView({
    super.key,
    required this.value,
    required this.refresh,
    required this.loadMore,
    required this.itemBuilder,
  });
  final AsyncValue<FeedState<T, M>> value;
  final Future<void> Function() refresh;
  final Future<void> Function({bool retry}) loadMore;
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
      await widget.refresh();
    } catch (_) {
      // 查询状态持有错误，按钮和下拉入口均消费同一个失败 Future。
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final value = widget.value;
    final data = !value.isLoading && !value.hasError ? value.value : null;
    return FeedPagination(
      controller: _scroll,
      dataSource: data?.source,
      dataRevision: data,
      canLoadMore: () => data?.canLoadMore ?? false,
      onLoadMore: () => widget.loadMore(retry: false),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (value.isLoading)
              gridSkeleton
            else if (value.hasError)
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
            if (data?.loadingMore == true)
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
                  onPressed: () => widget.loadMore(retry: true),
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
