import 'package:pili_aurora_next/pages/member_contribute/navigation.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/features/member_space/domain/contribute_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/tab2.dart';
import 'package:pili_aurora_next/pages/member_article/view.dart';
import 'package:pili_aurora_next/pages/member_audio/view.dart';
import 'package:pili_aurora_next/pages/member_comic/view.dart';
import 'package:pili_aurora_next/pages/member_opus/view.dart';
import 'package:pili_aurora_next/pages/member_season_series/view.dart';
import 'package:pili_aurora_next/pages/member_video/view.dart';
import 'package:material_ui/material_ui.dart';

class MemberContribute extends StatefulWidget {
  const MemberContribute({
    super.key,
    this.heroTag,
    required this.items,
    required this.controller,
    required this.navigation,
    required this.mid,
  });

  final String? heroTag;
  final List<SpaceTab2Item> items;
  final TabController? controller;
  final SpaceArchiveNavigation navigation;
  final int mid;

  @override
  State<MemberContribute> createState() => _MemberContributeState();
}

class _MemberContributeState extends State<MemberContribute>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return widget.controller != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                isScrollable: true,
                tabs: widget.items
                    .map((item) => Tab(text: item.title))
                    .toList(),
                tabAlignment: TabAlignment.start,
                controller: widget.controller,
                dividerHeight: 0,
                indicatorWeight: 0,
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 8,
                ),
                indicator: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle:
                    TabBarTheme.of(
                      context,
                    ).labelStyle?.copyWith(fontSize: 14) ??
                    const TextStyle(fontSize: 14),
                labelColor: theme.colorScheme.onSecondaryContainer,
                unselectedLabelColor: theme.colorScheme.outline,
              ),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  controller: widget.controller,
                  children: widget.items.map(_getPageFromType).toList(),
                ),
              ),
            ],
          )
        : widget.items.isNotEmpty
        ? _getPageFromType(widget.items.first)
        : scrollableError;
  }

  Widget _getPageFromType(SpaceTab2Item item) {
    final isSingle = widget.controller == null;
    return switch (item.param) {
      'video' => MemberVideo(
        navigation: widget.navigation,
        type: ContributeType.video,
        heroTag: widget.heroTag,
        mid: widget.mid,
        title: item.title,
        isSingle: isSingle,
      ),
      'charging_video' => MemberVideo(
        navigation: widget.navigation,
        type: ContributeType.charging,
        heroTag: widget.heroTag,
        mid: widget.mid,
        title: item.title,
      ),
      'article' => MemberArticle(
        heroTag: widget.heroTag,
        mid: widget.mid,
      ),
      'opus' => MemberOpus(
        filters: item.filter,
        heroTag: widget.heroTag,
        mid: widget.mid,
        isSingle: isSingle,
      ),
      'audio' => MemberAudio(
        heroTag: widget.heroTag,
        mid: widget.mid,
      ),
      'comic' => MemberComic(
        heroTag: widget.heroTag,
        mid: widget.mid,
      ),
      'season_video' => MemberVideo(
        navigation: widget.navigation,
        type: ContributeType.season,
        heroTag: widget.heroTag,
        mid: widget.mid,
        seasonId: item.seasonId,
        title: item.title,
      ),
      'series' => MemberVideo(
        navigation: widget.navigation,
        type: ContributeType.series,
        heroTag: widget.heroTag,
        mid: widget.mid,
        seriesId: item.seriesId,
        title: item.title,
      ),
      'ugcSeason' => SeasonSeriesPage(
        navigation: widget.navigation,
        mid: widget.mid,
        heroTag: widget.heroTag,
      ),
      _ => Center(child: Text(item.title!)),
    };
  }
}
