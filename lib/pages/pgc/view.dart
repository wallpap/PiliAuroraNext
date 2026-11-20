import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';

import 'dart:math';

import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/inactive_feed_sliver.dart';
import 'package:pili_aurora_next/common/widgets/button/more_btn.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/fav_type.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_pgc/list.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_result/list.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_timeline/result.dart';
import 'package:pili_aurora_next/features/content_discovery/application/pgc_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/pages/pgc/widgets/pgc_card_v.dart';
import 'package:pili_aurora_next/pages/pgc/widgets/pgc_card_v_timeline.dart';
import 'package:pili_aurora_next/pages/pgc_index/view.dart';
import 'package:pili_aurora_next/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PgcPage extends ConsumerStatefulWidget {
  const PgcPage({
    super.key,
    required this.tabType,
    this.register,
  });

  final HomeTabType tabType;
  final VoidCallback Function(DiscoveryPageHandle)? register;

  @override
  ConsumerState<PgcPage> createState() => _PgcPageState();
}

class _PgcPageState extends ConsumerState<PgcPage>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  final _scroll = ScrollController(), _followScroll = ScrollController();
  PgcQuery get _query =>
      (owner: _owner, cinema: widget.tabType == HomeTabType.cinema);
  PgcFeed get controller => ref.read(pgcFeedProvider(_query).notifier);
  PgcFollows get follows => ref.read(pgcFollowsProvider(_query).notifier);
  Future<void> _refresh() => Future.wait([
    controller.onRefresh(),
    follows.onRefresh(),
    if (ref.read(showPgcTimelineProvider) &&
        widget.tabType == HomeTabType.bangumi)
      ref.read(pgcTimelineProvider(_owner).notifier).onRefresh(),
  ]);
  Future<void> _timelineRefresh() =>
      ref.read(pgcTimelineProvider(_owner).notifier).onRefresh();
  VoidCallback? _unregister;
  @override
  void initState() {
    super.initState();
    _unregister = widget.register?.call(
      DiscoveryPageHandle(
        () => _scroll,
        _refresh,
        readSnapshot: () => ref.read(pgcFeedProvider(_query)),
      ),
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    _scroll.dispose();
    _followScroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ThemeData theme = Theme.of(context);
    final state = ref.watch(pgcFeedProvider(_query));
    final showTimeline =
        widget.tabType == HomeTabType.bangumi &&
        ref.watch(showPgcTimelineProvider);
    final timeline = showTimeline
        ? ref.watch(pgcTimelineProvider(_owner))
        : null;
    return refreshIndicator(
      onRefresh: _refresh,
      child: FeedPagination(
        controller: _scroll,
        dataSource: state.source,
        dataRevision: state,
        canLoadMore: () => state.canLoadMore,
        onLoadMore: controller.onLoadMore,
        prefetchExtent: () => 300,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildFollow(theme),
            if (timeline != null) ...[
              if (timeline.loading is Success && timeline.error != null)
                DiscoveryFooter(error: timeline.error, retry: _timelineRefresh),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      Grid.smallCardWidth / 2 / 0.75 +
                      MediaQuery.textScalerOf(context).scale(96),
                  child: _buildTimeline(
                    theme,
                    timeline.loading,
                    timeline.metadata,
                  ),
                ),
              ),
            ],
            ..._buildRcmd(theme),
            DiscoveryFooter(error: state.error, retry: controller.retry),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(
    ThemeData theme,
    LoadingState<List<TimelineResult>> loadingState,
    String? warning,
  ) => switch (loadingState) {
    Loading() => m3eLoading,
    Success(:final response) =>
      response.isNotEmpty
          ? Builder(
              builder: (context) {
                final initialIndex = max(
                  0,
                  response.indexWhere((item) => item.isToday == 1),
                );
                return DefaultTabController(
                  initialIndex: initialIndex,
                  length: response.length,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 16),
                          Text(
                            '追番时间表',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TabBar(
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              dividerHeight: 0,
                              overlayColor: const WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
                              splashFactory: NoSplash.splashFactory,
                              padding: const EdgeInsets.only(right: 10),
                              indicatorPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 10,
                              ),
                              indicator: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(20),
                                ),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor:
                                  theme.colorScheme.onSecondaryContainer,
                              labelStyle:
                                  TabBarTheme.of(
                                    context,
                                  ).labelStyle?.copyWith(fontSize: 14) ??
                                  const TextStyle(fontSize: 14),
                              dividerColor: Colors.transparent,
                              tabs: response.map(
                                (item) {
                                  return Tab(
                                    text:
                                        '${item.date ?? ''} ${item.isToday == 1 ? '今天' : switch (item.dayOfWeek) {
                                                1 => '周一',
                                                2 => '周二',
                                                3 => '周三',
                                                4 => '周四',
                                                5 => '周五',
                                                6 => '周六',
                                                7 => '周日',
                                                _ => '',
                                              }}',
                                  );
                                },
                              ).toList(),
                            ),
                          ),
                        ],
                      ),
                      if (warning != null)
                        TextButton(
                          onPressed: _timelineRefresh,
                          child: Text(warning),
                        ),
                      Expanded(
                        child: TabBarView(
                          physics: const NeverScrollableScrollPhysics(),
                          children: response.map((item) {
                            final episodes = item.episodes;
                            if (episodes == null || episodes.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              scrollDirection: Axis.horizontal,
                              itemCount: episodes.length,
                              padding: EdgeInsets.zero,
                              itemBuilder: (context, index) {
                                return Container(
                                  width: Grid.smallCardWidth / 2,
                                  margin: EdgeInsets.only(
                                    left: Style.safeSpace,
                                    right: index == episodes.length - 1
                                        ? Style.safeSpace
                                        : 0,
                                  ),
                                  child: PgcCardVTimeline(
                                    item: episodes[index],
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : const SizedBox.shrink(),
    Error(:final errMsg) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _timelineRefresh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        child: Text(
          errMsg ?? '',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  };

  List<Widget> _buildRcmd(ThemeData theme) => [
    _buildRcmdTitle(theme),
    SliverPadding(
      padding: const EdgeInsets.only(
        left: Style.safeSpace,
        right: Style.safeSpace,
        bottom: 100,
      ),
      sliver: _buildRcmdBody(ref.watch(pgcFeedProvider(_query)).loading),
    ),
  ];

  Widget _buildRcmdTitle(ThemeData theme) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(
        top: 10,
        bottom: 10,
        left: 16,
        right: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '推荐',
            style: theme.textTheme.titleMedium,
          ),
          moreTextButton(
            padding: const EdgeInsets.symmetric(vertical: 2),
            onTap: () {
              if (widget.tabType == HomeTabType.bangumi) {
                Get.to(const PgcIndexPage());
              } else {
                Get.to(const PgcIndexTabs());
              }
            },
            color: theme.colorScheme.secondary,
          ),
        ],
      ),
    ),
  );

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth * 0.6,
    childAspectRatio: 0.75,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(50),
  );

  Widget _buildRcmdBody(LoadingState<List<PgcIndexItem>> loadingState) {
    return switch (loadingState) {
      Loading() => const SliverToBoxAdapter(),
      Success(:final response) =>
        response.isNotEmpty
            ? InactiveFeedSliver(
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemBuilder: (context, index) {
                    return PgcCardVPgcIndex(item: response[index]);
                  },
                  itemCount: response.length,
                ),
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _buildFollow(ThemeData theme) => SliverToBoxAdapter(
    child: Consumer(
      builder: (context, ref, _) => ref.watch(mainAccountProvider).isLogin
          ? Column(
              children: [
                _buildFollowTitle(theme),
                SizedBox(
                  height:
                      Grid.smallCardWidth / 2 / 0.75 +
                      MediaQuery.textScalerOf(context).scale(50),
                  child: _buildFollowBody(
                    ref.watch(pgcFollowsProvider(_query)).loading,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    ),
  );

  Widget _buildFollowTitle(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(left: 16),
    child: Row(
      children: [
        Text(
          '最近${widget.tabType == HomeTabType.bangumi ? '追番' : '追剧'}${(ref.watch(pgcFollowsProvider(_query)).metadata ?? -1) < 0 ? '' : ' ${ref.watch(pgcFollowsProvider(_query)).metadata}'}',
          style: theme.textTheme.titleMedium,
        ),
        const Spacer(),
        IconButton(
          tooltip: '刷新',
          onPressed: follows.onRefresh,
          icon: const Icon(
            Icons.refresh,
            size: 20,
          ),
        ),
        Consumer(
          builder: (context, ref, _) => ref.watch(mainAccountProvider).isLogin
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: moreTextButton(
                    text: '查看全部',
                    onTap: () => Get.toNamed(
                      '/fav',
                      arguments: widget.tabType == HomeTabType.bangumi
                          ? FavTabType.bangumi.index
                          : FavTabType.cinema.index,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: theme.colorScheme.secondary,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );

  Widget _buildFollowBody(LoadingState<List<FavPgcItemModel>> loadingState) {
    return switch (loadingState) {
      Loading() => m3eLoading,
      Success(:final response) =>
        response.isNotEmpty
            ? FeedPagination(
                controller: _followScroll,
                dataSource: ref.watch(pgcFollowsProvider(_query)).source,
                dataRevision: ref.watch(pgcFollowsProvider(_query)),
                canLoadMore: () =>
                    ref.read(pgcFollowsProvider(_query)).canLoadMore,
                onLoadMore: follows.onLoadMore,
                prefetchExtent: () => 150,
                child: Column(
                  children: [
                    if (ref.watch(pgcFollowsProvider(_query)).error
                        case final error?)
                      TextButton(
                        onPressed: follows.retry,
                        child: Text('$error · 重试'),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _followScroll,
                        scrollDirection: Axis.horizontal,
                        itemCount: response.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          return Container(
                            width: Grid.smallCardWidth / 2,
                            margin: EdgeInsets.only(
                              left: Style.safeSpace,
                              right: index == response.length - 1
                                  ? Style.safeSpace
                                  : 0,
                            ),
                            child: PgcCardV(item: response[index]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            : Center(
                child: Text(
                  '还没有${widget.tabType == HomeTabType.bangumi ? '追番' : '追剧'}',
                ),
              ),
      Error(:final errMsg) => Center(
        child: TextButton(
          onPressed: follows.retry,
          child: Text('${errMsg ?? ''} · 重试'),
        ),
      ),
    };
  }
}
