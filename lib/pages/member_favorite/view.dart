import 'package:pili_aurora_next/common/skeleton/video_card_h.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/application/space_favorites.dart';
import 'package:pili_aurora_next/pages/member_favorite/widget/item.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:material_ui/material_ui.dart';

class MemberFavorite extends ConsumerStatefulWidget {
  const MemberFavorite({
    super.key,
    required this.heroTag,
    required this.mid,
  });

  final String? heroTag;
  final int mid;

  @override
  ConsumerState<MemberFavorite> createState() => _MemberFavoriteState();
}

class _MemberFavoriteState extends ConsumerState<MemberFavorite>
    with AutomaticKeepAliveClientMixin, GridMixin {
  @override
  bool get wantKeepAlive => true;

  final _owner = Object();
  SpaceFavoritesQuery get _query => (owner: _owner, mid: widget.mid);
  SpaceFavorites get _favorites =>
      ref.read(spaceFavoritesProvider(_query).notifier);
  bool _showFolders = true;
  bool _showSubscriptions = true;
  bool _returnToTop = false;

  bool _consumeReturnToTop() {
    final flag = _returnToTop;
    _returnToTop = false;
    return flag;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final state = ref.watch(spaceFavoritesProvider(_query));
    return refreshIndicator(
      isClampingScrollPhysics: true,
      onRefresh: _favorites.refresh,
      child: CustomScrollView(
        physics: _FavScrollPhysics(returnToTop: _consumeReturnToTop),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
            ),
            sliver: _buildBody(theme, state),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<FavoriteSections> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => SliverPadding(
        padding: const EdgeInsets.only(top: 7),
        sliver: SliverGrid(
          gridDelegate: gridDelegate,
          delegate: const SliverSingleChildDelegate(
            count: 10,
            child: VideoCardHSkeleton(),
          ),
        ),
      ),
      Success(:final response) =>
        response.folders != null && response.subscriptions != null
            ? SliverMainAxisGroup(
                slivers: [
                  _buildItem(theme, response.folders!, subscribed: false),
                  _buildItem(theme, response.subscriptions!, subscribed: true),
                ],
              )
            : HttpError(onReload: () => _favorites.refresh(clear: true)),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: () => _favorites.refresh(clear: true),
      ),
    };
  }

  Widget _buildItem(
    ThemeData theme,
    FavoriteSection data, {
    required bool subscribed,
  }) {
    final expanded = subscribed ? _showSubscriptions : _showFolders;
    return SliverMainAxisGroup(
      slivers: [
        SliverPinnedHeader(
          child: Material(
            color: theme.colorScheme.surface,
            child: InkWell(
              onTap: () => setState(() {
                if (subscribed) {
                  _showSubscriptions = !_showSubscriptions;
                } else {
                  _returnToTop = _showFolders;
                  _showFolders = !_showFolders;
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      TextSpan(
                        text: ' ${data.name}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      TextSpan(
                        text: ' ${data.count}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (expanded && data.items.isNotEmpty)
          SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: data.items.length,
            itemBuilder: (context, index) {
              final item = data.items[index];
              return SizedBox(
                height: 110,
                child: MemberFavItem(
                  item: item,
                  onDelete: _favorites.deletionAction(subscribed, item),
                ),
              );
            },
          ),
        if (expanded && data.nextPage != null)
          SliverToBoxAdapter(child: _buildLoadMoreItem(theme, subscribed)),
      ],
    );
  }

  Widget _buildLoadMoreItem(ThemeData theme, bool subscribed) {
    return Padding(
      padding: const .only(top: 7),
      child: InkWell(
        onTap: () async {
          final result = await _favorites.more(subscribed: subscribed);
          if (mounted && result is Error) result.toast();
        },
        child: Container(
          height: 40,
          alignment: .center,
          child: Text(
            '查看更多内容',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

class _FavScrollPhysics extends AlwaysScrollableScrollPhysics {
  const _FavScrollPhysics({super.parent, required this.returnToTop});

  final bool Function() returnToTop;

  @override
  _FavScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FavScrollPhysics(
      parent: buildParent(ancestor),
      returnToTop: returnToTop,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (returnToTop()) {
      return 0;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}
