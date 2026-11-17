import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/community/application/member_dynamics.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class MemberDynamicsPage extends ConsumerStatefulWidget {
  const MemberDynamicsPage({super.key, this.mid});

  final int? mid;

  @override
  ConsumerState<MemberDynamicsPage> createState() => _MemberDynamicsPageState();
}

class _MemberDynamicsPageState extends ConsumerState<MemberDynamicsPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  final _owner = Object();
  MemberDynamicsQuery get _query =>
      (owner: _owner, mid: widget.mid ?? int.parse(Get.parameters['mid']!));
  MemberDynamics get controller =>
      ref.read(memberDynamicsProvider(_query).notifier);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return widget.mid == null
        ? SimpleScaffold(
            appBar: AppBar(title: const Text('我的动态')),
            body: Padding(
              padding: EdgeInsets.only(
                left: padding.left,
                right: padding.right,
              ),
              child: _buildBody(padding),
            ),
          )
        : _buildBody(padding);
  }

  Widget _buildBody(EdgeInsets padding) {
    final state = ref.watch(memberDynamicsProvider(_query));
    return refreshIndicator(
      isClampingScrollPhysics: widget.mid != null,
      onRefresh: controller.onRefresh,
      child: FeedPagination.notifications(
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: controller.onLoadMore,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(bottom: padding.bottom + 100),
              sliver: buildPage(_buildContent(state.loading)),
            ),
            DiscoveryFooter(error: state.error, retry: controller.retry),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(LoadingState<List<DynamicItemModel>> loadingState) {
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
    final query = _query;
    final notifier = controller;
    final source = ref.read(memberDynamicsProvider(query)).source;
    final current = notifier.captureItem(item);
    Future<void> run(Object id, bool? wasPinned) async {
      if (!current() || id.toString() != item.idStr.toString()) return;
      final result = await (wasPinned == null
          ? notifier.removeItem(item, source)
          : notifier.setPinned(item, source, wasPinned));
      // 删除成功后条目已消失，只核对查询和页面归属再交付提示。
      if (!mounted ||
          query != _query ||
          !identical(source, ref.read(memberDynamicsProvider(query)).source))
        return;
      if (result.isSuccess) {
        SmartDialog.showToast(
          wasPinned == null
              ? '删除成功'
              : wasPinned
              ? '取消置顶成功'
              : '置顶成功',
        );
      } else {
        result.toast();
      }
    }

    return DynamicPanel(
      item: item,
      onRemove: (id) => run(id, null),
      onSetTop: (wasPinned, id) => run(id, wasPinned),
    );
  }
}
