import 'dart:async';

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
import 'package:pili_aurora_next/pages/dynamics_tab/controller.dart';
import 'package:pili_aurora_next/utils/extension/get_ext.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class DynamicsTabPage extends StatefulWidget {
  const DynamicsTabPage({
    super.key,
    required this.dynamicsType,
    required this.onRegister,
    required this.onRefreshAuthors,
  });

  final DynamicsTabType dynamicsType;
  final VoidCallback Function(DiscoveryPageHandle) onRegister;
  final Future<void> Function() onRefreshAuthors;

  @override
  State<DynamicsTabPage> createState() => _DynamicsTabPageState();
}

class _DynamicsTabPageState extends State<DynamicsTabPage> with DynMixin {
  VoidCallback? _unregister;
  late final DynamicsTabController controller;

  @override
  void initState() {
    controller = Get.putOrFind(
      () => DynamicsTabController(
        dynamicsType: widget.dynamicsType,
        selectedHost: () => ProviderScope.containerOf(
          context,
          listen: false,
        ).read(dynamicsSelectionProvider).hostMid,
        banned: () => ProviderScope.containerOf(
          context,
          listen: false,
        ).read(dynamicsSelectionProvider).banned,
      ),
      tag: widget.dynamicsType.name,
    );
    super.initState();
    _unregister = widget.onRegister(
      DiscoveryPageHandle(
        () => controller.scrollController,
        controller.onRefresh,
      ),
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    Get.delete<DynamicsTabController>(tag: widget.dynamicsType.name);
    super.dispose();
  }

  Future<void> onRefresh() {
    return Future.wait([widget.onRefreshAuthors(), controller.onRefresh()]);
  }

  @override
  Widget build(BuildContext context) {
    return refreshIndicator(
      onRefresh: onRefresh,
      child: FeedPagination(
        prefetchExtent: () =>
            controller.scrollController.position.viewportDimension,
        controller: controller.scrollController,
        dataChanges: controller.loadingState.stream,
        canLoadMore: () => controller.canLoadMore && !controller.isLoading,
        onLoadMore: controller.onLoadMore,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          key: PageStorageKey(widget.dynamicsType.name),
          physics: const AlwaysScrollableScrollPhysics(),
          controller: controller.scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: buildPage(
                Obx(() => _buildBody(controller.loadingState.value)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<DynamicItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
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
      onRemove: (idStr) => controller.onRemove(index, idStr),
      onBlock: () => controller.onBlock(index),
      onUnfold: () => controller.onUnfold(item, index),
    );
  }
}
