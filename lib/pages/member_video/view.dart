import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadMixin, ReloadScrollPhysics;
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/contribute_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:pili_aurora_next/pages/member_contribute/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/pages/member_video/widgets/video_card_h_member_video.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicatorState;

class MemberVideo extends ConsumerStatefulWidget {
  const MemberVideo({
    super.key,
    required this.type,
    required this.heroTag,
    required this.mid,
    this.seasonId,
    this.seriesId,
    this.title,
    this.navigation,
    this.isSingle = false,
  });

  final SpaceArchiveNavigation? navigation;
  final ContributeType type;
  final String? heroTag;
  final int mid;
  final int? seasonId;
  final int? seriesId;
  final String? title;
  final bool isSingle;

  @override
  ConsumerState<MemberVideo> createState() => _MemberVideoState();
}

class _MemberVideoState extends ConsumerState<MemberVideo>
    with
        AutomaticKeepAliveClientMixin,
        GridMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        LazyFabMixin,
        ReloadMixin {
  @override
  bool get wantKeepAlive => true;

  final _owner = Object();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  bool _locating = false;
  bool _loadPrevious = false;
  SpaceArchiveQuery get _query => (
    owner: _owner,
    mid: widget.mid,
    type: widget.type,
    season: widget.seasonId,
    series: widget.seriesId,
  );
  SpaceArchive get _archive => ref.read(spaceArchiveProvider(_query).notifier);
  SpaceArchiveState get _snapshot => ref.read(spaceArchiveProvider(_query));
  bool get _isVideo => widget.type == .video;
  String? get _anchor => _isVideo ? widget.navigation?.fromViewAid : null;

  void _onlyInnerScroll(bool value) {
    final state = widget.navigation?.scrollState();
    if (state != null && state.mounted) state.onlyInnerScroll = value;
  }

  Future<void> _reload() async {
    setState(() {
      _locating = _loadPrevious = false;
      reload = true;
    });
    _onlyInnerScroll(false);
    await _archive.refresh(clear: true);
  }

  Future<void> _openPlayback() async {
    final result = await _archive.playback(
      username: widget.navigation?.username,
      title: widget.title,
    );
    if (!mounted || result == null) return;
    if (result case Error error) {
      error.toast();
    } else if (result.dataOrNull case final video?) {
      PageUtils.toVideoPage(
        aid: video.aid,
        bvid: video.bvid,
        cid: video.cid,
        dimension: video.dimension,
        cover: video.cover,
        title: video.title,
        isVertical: video.isVertical,
        extraArguments: video.arguments,
      );
    }
  }

  void _jumpToIndex(int index) {
    final layout = gridDelegate.layoutCache;
    if (layout == null) return;
    final scrollOffset = layout.getGeometryForChildIndex(index).scrollOffset;
    try {
      final state = widget.navigation?.scrollState();
      if (state != null && state.mounted) {
        state.innerNestedPositions.first.localJumpTo(scrollOffset);
      }
    } catch (e, stackTrace) {
      logger.w('jump error: $e', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _onRefresh() async {
    if (!_loadPrevious) {
      await _archive.refresh();
      return;
    }
    _loadPrevious = false;
    final source = _snapshot.source;
    final result = await _archive.previous();
    if (!mounted || !identical(source, _snapshot.source)) return;
    if (!_snapshot.hasPrevious) _onlyInnerScroll(false);
    if (result case Error error) {
      error.toast();
      return;
    }
    final added = result.data;
    if (added > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(source, _snapshot.source)) _jumpToIndex(added);
      });
    }
  }

  Future<void> _locate() async {
    final anchor = _anchor;
    if (anchor == null) return;
    final index =
        _snapshot.loading.dataOrNull?.indexWhere(
          (item) => item.param == anchor,
        ) ??
        -1;
    setState(() => _locating = true);
    if (index >= 0) {
      _jumpToIndex(index);
    } else {
      _onlyInnerScroll(true);
      reload = true;
      await _archive.refresh(clear: true, anchor: anchor);
    }
  }

  @override
  void dispose() {
    if (_locating) _onlyInnerScroll(false);
    super.dispose();
  }

  @override
  Widget fabAnimWrapper({required Widget child}) {
    return NotificationListener<ScrollNotification>(
      onNotification: onNotification,
      child: child,
    );
  }

  @override
  bool onNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      return super.onNotification(notification);
    }
    if (_locating) {
      if (notification is ScrollEndNotification &&
          notification.metrics.pixels == 0) {
        if (_snapshot.hasPrevious && !_snapshot.busy && !_loadPrevious) {
          if (_refreshKey.currentState case final refresh?) {
            _loadPrevious = true;
            refresh.show();
          }
        }
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(spaceArchiveProvider(_query));
    ref.listen(mainAccountProvider, (_, _) {
      if (_locating) _onlyInnerScroll(false);
      _locating = _loadPrevious = false;
      reload = true;
    });
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    Widget child = FeedPagination.notifications(
      dataSource: state.source,
      dataRevision: state,
      canLoadMore: () => state.canLoadMore,
      onLoadMore: _archive.more,
      child: CustomScrollView(
        physics: ReloadScrollPhysics(controller: this),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(bottom: padding.bottom + 100),
            sliver: _buildBody(theme, state.loading),
          ),
        ],
      ),
    );
    if (_anchor?.isNotEmpty == true) {
      child = ScaffoldLayout(
        body: fabAnimWrapper(child: child),
        fab: !_locating
            ? SlideTransition(
                position: fabAnimation,
                child: Padding(
                  padding: .only(
                    right: kFloatingActionButtonMargin,
                    bottom: kFloatingActionButtonMargin + padding.bottom,
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: _locate,
                    label: const Text('定位至上次观看'),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    }
    return refreshIndicator(
      key: _refreshKey,
      isClampingScrollPhysics: true,
      onRefresh: _onRefresh,
      child: child,
    );
  }

  @override
  Widget get gridSkeleton => SliverPadding(
    padding: widget.isSingle ? const EdgeInsets.only(top: 7) : EdgeInsets.zero,
    sliver: super.gridSkeleton,
  );

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<SpaceArchiveItem>> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? SliverMainAxisGroup(
                slivers: [
                  _buildHeader(theme),
                  SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemBuilder: (context, index) {
                      return VideoCardHMemberVideo(
                        videoItem: response[index],
                        fromViewAid: _anchor,
                      );
                    },
                    itemCount: response.length,
                  ),
                  if (_snapshot.pageError case final error?)
                    HttpError(
                      errMsg: error.errMsg,
                      onReload: () => _archive.more(retry: true),
                    ),
                ],
              )
            : HttpError(onReload: _reload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _reload,
      ),
    };
  }

  Widget _buildHeader(ThemeData theme) {
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2.5, 8, 2.5),
        child: Row(
          children: [
            ?_buildCount(),
            ?_buildEpisodeBtn(theme),
            const Spacer(),
            _buildSortBtn(theme),
          ],
        ),
      ),
    );
  }

  Widget? _buildCount() {
    final count = _snapshot.count;
    if (count != null) {
      return Text(
        '共$count视频',
        style: const TextStyle(fontSize: 13),
      );
    }
    return null;
  }

  Widget? _buildEpisodeBtn(ThemeData theme) {
    final episodicButton = _snapshot.button;
    if (episodicButton?.uri?.isNotEmpty ?? false) {
      return Padding(
        padding: EdgeInsets.only(
          left: _snapshot.count != null ? 6 : 0,
        ),
        child: TextButton.icon(
          style: Style.buttonStyle,
          onPressed: _openPlayback,
          icon: Icon(
            Icons.play_circle_outline_rounded,
            size: 16,
            color: theme.colorScheme.secondary,
          ),
          label: Text(
            episodicButton?.text ?? '播放全部',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildSortBtn(ThemeData theme) {
    return TextButton.icon(
      style: Style.buttonStyle,
      onPressed: () {
        if (_snapshot.busy) return;
        setState(() {
          _locating = _loadPrevious = false;
          reload = true;
        });
        _onlyInnerScroll(false);
        _archive.toggleSort();
      },
      icon: Icon(
        Icons.sort,
        size: 16,
        color: theme.colorScheme.secondary,
      ),
      label: Text(
        _isVideo ? _snapshot.order.label : _snapshot.sort.label,
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.secondary,
        ),
      ),
    );
  }
}
