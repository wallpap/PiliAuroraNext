import 'package:pili_aurora_next/features/member_space/domain/profiles/space/tab2.dart';
import 'package:pili_aurora_next/common/skeleton/space_opus.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_opus/item.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:pili_aurora_next/features/member_space/application/space_listings.dart';
import 'package:pili_aurora_next/pages/member_opus/widgets/space_opus_item.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class MemberOpus extends ConsumerStatefulWidget {
  const MemberOpus({
    super.key,
    this.isSingle = false,
    this.filters,
    required this.heroTag,
    required this.mid,
  });

  final List<SpaceTabFilter>? filters;
  final bool isSingle;
  final String? heroTag;
  final int mid;

  @override
  ConsumerState<MemberOpus> createState() => _MemberOpusState();
}

class _MemberOpusState extends ConsumerState<MemberOpus>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        LazyFabMixin {
  final _owner = Object();
  SpaceTabFilter _filter = const SpaceTabFilter(text: '全部图文', tabName: '图文');
  SpaceOpusQuery get _query =>
      (owner: _owner, mid: widget.mid, filter: _filter.meta);
  SpaceOpus get _controller => ref.read(spaceOpusProvider(_query).notifier);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final state = ref.watch(spaceOpusProvider(_query));
    return ScaffoldLayout(
      body: FeedPagination.notifications(
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: _controller.onLoadMore,
        child: refreshIndicator(
          isClampingScrollPhysics: true,
          onRefresh: _controller.onRefresh,
          child: fabAnimWrapper(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: widget.isSingle ? 12 : 0,
                    left: Style.safeSpace,
                    right: Style.safeSpace,
                    bottom: bottom + 100,
                  ),
                  sliver: _buildBody(state.loading),
                ),
                if ((state.loading is Success ? state.error : null)
                    case final error?)
                  SliverToBoxAdapter(
                    child: TextButton(
                      onPressed: _controller.retry,
                      child: Text('$error，点击重试'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      fab: widget.filters?.isNotEmpty == true
          ? SlideTransition(
              position: fabAnimation,
              child: Padding(
                padding: .only(
                  right: kFloatingActionButtonMargin,
                  bottom: kFloatingActionButtonMargin + bottom,
                ),
                child: FloatingActionButton.extended(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => SimpleDialog(
                      clipBehavior: Clip.hardEdge,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                      children: widget.filters!
                          .map(
                            (e) => ListTile(
                              dense: true,
                              onTap: () {
                                if (e == _filter) {
                                  return;
                                }
                                Navigator.of(context).pop();
                                if (mounted) setState(() => _filter = e);
                              },
                              tileColor: e == _filter
                                  ? ColorScheme.of(context).onInverseSurface
                                  : null,
                              title: Text(
                                e.text ?? e.tabName!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  icon: const Icon(size: 20, Icons.sort),
                  label: Text(_filter.text ?? _filter.tabName!),
                ),
              ),
            )
          : null,
    );
  }

  late final gridDelegate = SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: Grid.smallCardWidth,
    mainAxisSpacing: Style.safeSpace,
    crossAxisSpacing: Style.safeSpace,
  );

  Widget _buildBody(LoadingState<List<SpaceOpusItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => SliverWaterfallFlow(
        gridDelegate: gridDelegate,
        delegate: const SliverSingleChildDelegate(
          count: 10,
          child: SpaceOpusSkeleton(),
        ),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverWaterfallFlow(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (_, index) {
                    return SpaceOpusItem(item: response[index]);
                  },
                  childCount: response.length,
                ),
              )
            : HttpError(onReload: _controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  @override
  bool get wantKeepAlive => true;
}
