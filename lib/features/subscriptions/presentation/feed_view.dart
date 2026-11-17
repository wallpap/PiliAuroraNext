import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_library.dart';
import 'package:pili_aurora_next/utils/grid.dart';

class SubscriptionFeedView extends StatefulWidget {
  const SubscriptionFeedView({
    super.key,
    required this.value,
    required this.feed,
    required this.itemBuilder,
    this.header,
    this.progress = '',
    this.enabled = true,
  });
  final AsyncValue<SubscriptionState> value;
  final SubscriptionFeed feed;
  final Widget Function(Object) itemBuilder;
  final Widget? header;
  final String progress;
  final bool enabled;
  @override
  State<SubscriptionFeedView> createState() => _SubscriptionFeedViewState();
}

class _SubscriptionFeedViewState extends State<SubscriptionFeedView>
    with GridMixin {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.enabled) return;
    try {
      await widget.feed.refresh();
    } catch (_) {
      // 查询错误由同一份 AsyncValue 展示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final data = !value.isLoading && !value.hasError ? value.value : null;
    final padding = MediaQuery.viewPaddingOf(context);
    return FeedPagination(
      controller: _scroll,
      dataSource: data?.source,
      dataRevision: data,
      canLoadMore: () => widget.enabled && (data?.canLoadMore ?? false),
      onLoadMore: widget.feed.loadMore,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ?widget.header,
            if (widget.progress.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(widget.progress),
                ),
              ),
            if (value.isLoading)
              gridSkeleton
            else if (value.hasError)
              HttpError(errMsg: value.error.toString(), onReload: _refresh)
            else if (data == null || data.items.isEmpty)
              HttpError(onReload: _refresh)
            else
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 7,
                  left: padding.left,
                  right: padding.right,
                ),
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemCount: data.items.length,
                  itemBuilder: (_, index) =>
                      widget.itemBuilder(data.items[index]),
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
                  onPressed: widget.enabled
                      ? () => widget.feed.loadMore(retry: true)
                      : null,
                  child: Text('$error，点击重试'),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: padding.bottom + 100)),
          ],
        ),
      ),
    );
  }
}
