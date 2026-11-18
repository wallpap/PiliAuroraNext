import 'dart:math';

import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadScrollPhysics, ReloadMixin;
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/models/remote/popular/popular_series_one/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/curated_feed.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/weekly_catalog.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PopularSeriesPage extends ConsumerStatefulWidget {
  const PopularSeriesPage({super.key});

  @override
  ConsumerState<PopularSeriesPage> createState() => _PopularSeriesPageState();
}

class _PopularSeriesPageState extends ConsumerState<PopularSeriesPage>
    with GridMixin, ReloadMixin {
  final _owner = Object();
  int? _number;
  WeeklyQuery get _query => (owner: _owner, number: _number);
  WeeklyFeed get _controller => ref.read(weeklyFeedProvider(_query).notifier);
  WeeklyCatalog? get _catalog => ref.read(weeklyFeedProvider(_query)).metadata;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weeklyFeedProvider(_query));
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(state.metadata?.config?.name ?? '每周必看'),
      ),
      body: refreshIndicator(
        onRefresh: _controller.onRefresh,
        child: CustomScrollView(
          physics: ReloadScrollPhysics(controller: this),
          slivers: [
            if (state.loading is Success && state.error != null)
              DiscoveryFooter(error: state.error, retry: _controller.retry),
            ViewSliverSafeArea(
              sliver: _buildBody(state.loading),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>> value) {
    switch (value) {
      case Loading():
        return gridSkeleton;
      case Success<List<HotVideoItemModel>>(:final response):
        Widget sliver;
        if (response.isNotEmpty) {
          sliver = SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: response.length,
            itemBuilder: (context, index) {
              final item = response[index];
              return VideoCardH(
                videoItem: item,
                onTap: () {
                  final config = _catalog?.config;
                  PageUtils.toVideoPage(
                    bvid: item.bvid,
                    cid: item.cid!,
                    dimension: item.dimension,
                    extraArguments: {
                      'sourceType': SourceType.playlist,
                      'favTitle': '每周必看 ${config?.label ?? ''}',
                      'mediaId': config?.mediaId,
                      'desc': true,
                      'oid': item.aid,
                      'isContinuePlaying': index != 0,
                    },
                  );
                },
              );
            },
          );
        } else {
          sliver = HttpError(onReload: _controller.onReload);
        }
        if (_catalog?.config case final config?) {
          sliver = SliverMainAxisGroup(
            slivers: [
              _buildSeriesList(config),
              sliver,
            ],
          );
        }
        return sliver;
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _controller.onReload,
        );
    }
  }

  Widget _buildSeriesList(PopularSeriesConfig config) {
    final colorScheme = ColorScheme.of(context);
    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final query = _query;
        final source = ref.read(weeklyFeedProvider(query)).source;
        final number = _catalog?.number;
        final seriesList = _catalog!.series;
        final size = MediaQuery.sizeOf(context);
        final padding = MediaQuery.viewPaddingOf(context);
        final width = min(
          min(
            size.width - padding.horizontal - 80,
            size.height - padding.vertical - 48,
          ),
          525.0,
        );
        final currIndex = seriesList.indexWhere((e) => e.number == number);
        final controller = ScrollController(
          initialScrollOffset: max(0, currIndex * 44 + 34 - width / 2),
        );
        showDialog(
          context: context,
          builder: (context) => Dialog(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: width,
              height: width,
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: seriesList.length,
                itemExtent: 44,
                itemBuilder: (context, index) {
                  final item = seriesList[index];
                  final isCurr = index == currIndex;
                  return ListTile(
                    dense: true,
                    minTileHeight: 44,
                    enabled: !isCurr,
                    onTap: () {
                      Get.back();
                      if (!isCurr &&
                          mounted &&
                          _query == query &&
                          identical(
                            ref.read(weeklyFeedProvider(query)).source,
                            source,
                          )) {
                        setState(() {
                          _number = item.number;
                          reload = true;
                        });
                      }
                    },
                    title: Text(
                      item.name!,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: isCurr ? const Icon(Icons.check, size: 20) : null,
                    contentPadding: const EdgeInsetsGeometry.symmetric(
                      horizontal: 16,
                    ),
                  );
                },
              ),
            ),
          ),
        ).whenComplete(controller.dispose);
      },
      child: Text.rich(
        style: TextStyle(
          height: 1,
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        strutStyle: const StrutStyle(height: 1, leading: 0, fontSize: 14),
        TextSpan(
          children: [
            TextSpan(text: config.label!),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                size: 18,
                Icons.keyboard_arrow_down,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    if (_catalog?.reminder case final reminder?) {
      child = Row(
        spacing: 16,
        children: [
          child,
          Text(
            reminder,
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      );
    }
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .only(left: 14, bottom: 7),
        child: child,
      ),
    );
  }
}
