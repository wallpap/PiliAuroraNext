import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_rankings.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/live/contribution_rank_type.dart';
import 'package:pili_aurora_next/features/playback/domain/live/contribution_rank/item.dart';
import 'package:pili_aurora_next/pages/member/widget/medal_widget.dart';
import 'package:pili_aurora_next/common/appearance/color_utils.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:pili_aurora_next/services/diagnostics/report_error.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ContributionRankPanel extends StatefulWidget {
  const ContributionRankPanel({
    super.key,
    required this.ruid,
    required this.roomId,
  });

  final Object ruid;
  final Object roomId;

  @override
  State<ContributionRankPanel> createState() => _ContributionRankPanelState();
}

class _ContributionRankPanelState extends State<ContributionRankPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _scope = Object();
  final _scroll = {
    for (final type in LiveContributionRankType.values)
      type: ScrollController(),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: LiveContributionRankType.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final scroll in _scroll.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 45,
          child: TabBar(
            controller: _tabController,
            tabs: LiveContributionRankType.values
                .map((e) => Tab(text: e.title))
                .toList(),
            dividerColor: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.3),
            onTap: (index) {
              if (!_tabController.indexIsChanging) {
                final scroll = _scroll[LiveContributionRankType.values[index]]!;
                if (scroll.hasClients) scroll.animToTop();
              }
            },
          ),
        ),
        Expanded(
          child: tabBarView(
            controller: _tabController,
            children: LiveContributionRankType.values
                .map(
                  (e) => _ContributionRankType(
                    query: (
                      (scope: _scope, anchor: widget.ruid, room: widget.roomId),
                      e,
                    ),
                    scroll: _scroll[e]!,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ContributionRankType extends ConsumerStatefulWidget {
  const _ContributionRankType({
    required this.query,
    required this.scroll,
  });

  final LiveContributionQuery query;
  final ScrollController scroll;

  @override
  ConsumerState<_ContributionRankType> createState() =>
      _ContributionRankTypeState();
}

class _ContributionRankTypeState extends ConsumerState<_ContributionRankType>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showScore = widget.query.$2 == .online_rank;
    final provider = liveContributionProvider(widget.query);
    final state = liveRankingResult(ref.watch(provider));
    void retry() => ref.invalidate(provider);
    return Material(
      type: .transparency,
      child: refreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: CustomScrollView(
          controller: widget.scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ViewSliverSafeArea(
              sliver: _buildBody(showScore, state, retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    bool showScore,
    LoadingState<List<LiveContributionRankItem>> state,
    VoidCallback retry,
  ) {
    return switch (state) {
      Loading() => linearLoading,
      Success(:final response) =>
        response.isNotEmpty
            ? SliverFixedExtentList.builder(
                itemCount: response.length,
                itemBuilder: (context, index) {
                  final item = response[index];
                  return _Item(
                    index: index,
                    item: item,
                    showScore: showScore,
                  );
                },
                itemExtent: 60,
              )
            : HttpError(onReload: retry),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: retry,
      ),
    };
  }

  @override
  bool get wantKeepAlive => true;
}

class _Item extends StatelessWidget {
  const _Item({
    required this.index,
    required this.item,
    required this.showScore,
  });

  final int index;
  final bool showScore;
  final LiveContributionRankItem item;

  @override
  Widget build(BuildContext context) {
    late final colorScheme = ColorScheme.of(context);
    Widget child = Text(item.name!);
    if (item.uinfoMedal case final uinfoMedal?) {
      try {
        child = Column(
          spacing: 4,
          crossAxisAlignment: .start,
          children: [
            child,
            MedalWidget.fromMedalInfo(
              medal: uinfoMedal,
              padding: MedalWidget.mediumPadding,
            ),
          ],
        );
      } catch (e, s) {
        if (kDebugMode) {
          reportError(e, s);
        }
      }
    }
    return InkWell(
      onTap: () => Get.toNamed('/member?mid=${item.uid}'),
      child: Padding(
        padding: const .only(left: 10, top: 9, bottom: 8, right: 16),
        child: Row(
          spacing: 10,
          children: [
            SizedBox(
              width: 32,
              child: Center(
                child: Text(
                  '${index + 1}',
                  textAlign: .center,
                  textScaler: .noScaling,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ColourUtils.index2Color(index, colorScheme.outline),
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            NetworkImgLayer(
              src: item.face,
              width: 42,
              height: 42,
              type: .avatar,
            ),
            Expanded(child: child),
            if (showScore)
              Text(
                item.score.toString(),
                style: TextStyle(color: colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}
