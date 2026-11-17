import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformAlwaysClampingPhysics;
import 'package:pili_aurora_next/features/community/application/dynamic_activity.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/common/dyn/repost_list/widgets/item.dart';
import 'package:material_ui/material_ui.dart';

class DynRepostPage extends ConsumerStatefulWidget {
  const DynRepostPage({super.key, required this.query, this.isPortrait = true});
  final DynamicActivityQuery query;
  final bool isPortrait;
  @override
  ConsumerState<DynRepostPage> createState() => _DynRepostPageState();
}

class _DynRepostPageState extends ConsumerState<DynRepostPage> {
  void _activate() => scheduleMicrotask(() {
    if (mounted) {
      unawaited(
        ref.read(dynamicRepostsProvider(widget.query).notifier).activate(),
      );
    }
  });
  @override
  void initState() {
    super.initState();
    _activate();
  }

  @override
  void didUpdateWidget(DynRepostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _activate();
  }

  @override
  Widget build(BuildContext context) {
    final provider = dynamicRepostsProvider(widget.query);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final items = state.loading.dataOrNull;
    final child = FeedPagination.notifications(
      dataSource: state.source,
      dataRevision: state,
      canLoadMore: () => state.canLoadMore,
      onLoadMore: notifier.onLoadMore,
      child: CustomScrollView(
        key: PageStorageKey(('repost', widget.query)),
        physics: widget.isPortrait
            ? platformAlwaysClampingPhysics
            : const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
            ),
            sliver: switch (state.loading) {
              Loading() => const SliverFillRemaining(child: m3eLoading),
              Error(:final errMsg) => HttpError(
                errMsg: errMsg,
                onReload: notifier.onReload,
              ),
              Success() =>
                items!.isEmpty
                    ? HttpError(onReload: notifier.onReload)
                    : SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            DynRepostItem(item: items[index]),
                      ),
            },
          ),
          DiscoveryFooter(error: state.error, retry: notifier.retry),
        ],
      ),
    );
    if (widget.isPortrait) return child;
    return refreshIndicator(onRefresh: notifier.onRefresh, child: child);
  }
}
