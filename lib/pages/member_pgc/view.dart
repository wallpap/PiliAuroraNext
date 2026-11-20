import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart'
    show m3eLoading;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';
import 'package:pili_aurora_next/features/member_space/application/space_listings.dart';
import 'package:pili_aurora_next/pages/member_pgc/widgets/pgc_card_v_member_pgc.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:material_ui/material_ui.dart';

class MemberBangumi extends ConsumerStatefulWidget {
  const MemberBangumi({
    super.key,
    required this.heroTag,
    required this.mid,
  });

  final String? heroTag;
  final int mid;

  @override
  ConsumerState<MemberBangumi> createState() => _MemberBangumiState();
}

class _MemberBangumiState extends ConsumerState<MemberBangumi>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _owner = Object();
  SpaceListQuery get _query => (owner: _owner, mid: widget.mid);
  SpaceBangumi get _controller =>
      ref.read(spaceBangumiProvider(_query).notifier);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(spaceBangumiProvider(_query));
    return FeedPagination.notifications(
      dataSource: state.source,
      dataRevision: state,
      canLoadMore: () => state.canLoadMore,
      onLoadMore: _controller.onLoadMore,
      child: refreshIndicator(
        isClampingScrollPhysics: true,
        onRefresh: _controller.onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: Style.safeSpace,
                right: Style.safeSpace,
                top: Style.safeSpace,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
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
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth * 0.6,
    childAspectRatio: 0.75,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(52),
  );

  Widget _buildBody(LoadingState<List<SpaceArchiveItem>?> loadingState) {
    return switch (loadingState) {
      Loading() => const SliverToBoxAdapter(
        child: SizedBox(height: 125, child: m3eLoading),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  return PgcCardVMemberPgc(
                    item: response[index],
                  );
                },
                itemCount: response.length,
              )
            : HttpError(onReload: _controller.onReload),
      Error error => HttpError(
        errMsg: error.toString(),
        onReload: _controller.onReload,
      ),
    };
  }
}
