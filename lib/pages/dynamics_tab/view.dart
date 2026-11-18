import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';

import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamics_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class DynamicsTabPage extends ConsumerStatefulWidget {
  const DynamicsTabPage({
    super.key,
    required this.dynamicsType,
    required this.onRegister,
    required this.onRefreshAuthors,
    this.onRefreshFeed,
  });

  final DynamicsTabType dynamicsType;
  final VoidCallback Function(DiscoveryPageHandle) onRegister;
  final Future<void> Function() onRefreshAuthors;
  final VoidCallback? onRefreshFeed;

  @override
  ConsumerState<DynamicsTabPage> createState() => _DynamicsTabPageState();
}

class _DynamicsTabPageState extends ConsumerState<DynamicsTabPage>
    with DynMixin {
  VoidCallback? _unregister;
  final _owner = Object();
  late final _scroll = ScrollController(
    keepScrollOffset: widget.dynamicsType != DynamicsTabType.up,
  );
  DynamicsQuery get _query => (
    owner: _owner,
    type: widget.dynamicsType,
    hostMid: widget.dynamicsType == DynamicsTabType.up
        ? ref.read(dynamicsSelectionProvider).hostMid
        : -1,
  );
  DynamicsFeed get controller =>
      ref.read(dynamicsFeedProvider(_query).notifier);
  @override
  void initState() {
    super.initState();
    _unregister = widget.onRegister(
      DiscoveryPageHandle(
        () => _scroll,
        () => controller.onRefresh(),
        readSnapshot: () => ref.read(dynamicsFeedProvider(_query)),
      ),
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> onRefresh() {
    widget.onRefreshFeed?.call();
    return Future.wait([widget.onRefreshAuthors(), controller.onRefresh()]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dynamicsType == DynamicsTabType.up) {
      ref.watch(dynamicsSelectionProvider.select((value) => value.hostMid));
    }
    final query = _query;
    final state = ref.watch(dynamicsFeedProvider(query));
    return refreshIndicator(
      onRefresh: onRefresh,
      child: FeedPagination(
        prefetchExtent: () => _scroll.position.viewportDimension,
        controller: _scroll,
        dataRevision: state,
        dataSource: state.source,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: controller.onLoadMore,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          key: query.type == DynamicsTabType.up
              ? ValueKey(query.hostMid)
              : PageStorageKey(query.type.name),
          physics: const AlwaysScrollableScrollPhysics(),
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: buildPage(
                _buildBody(state.loading),
              ),
            ),
            DiscoveryFooter(error: state.error, retry: controller.retry),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<DynamicItemModel>> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? GlobalData().dynamicsWaterfallFlow
                  ? SliverWaterfallFlow(
                      gridDelegate: dynGridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _itemBuilder(response, index),
                        childCount: response.length,
                      ),
                    )
                  : SliverList.builder(
                      itemBuilder: (context, index) =>
                          _itemBuilder(response, index),
                      itemCount: response.length,
                    )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    final item = list[index];
    return DynamicPanel(
      item: item,
      onRemove: (idStr) async {
        final query = _query;
        final current = controller.captureQuery();
        final result = await controller.onRemove(idStr.toString());
        if (!mounted || query != _query || !current()) return;
        if (result.isSuccess) {
          SmartDialog.showToast('删除成功');
        } else {
          result.toast();
        }
      },
      onBlock: () {
        if (widget.dynamicsType != DynamicsTabType.up) controller.remove(item);
      },
      onUnfold: () => controller.onUnfold(item),
    );
  }
}
