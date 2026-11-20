import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/features/content_discovery/application/related_videos.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:material_ui/material_ui.dart';

class RelatedVideoPanel extends StatefulWidget {
  const RelatedVideoPanel({super.key, required this.query});
  final ValueListenable<RelatedVideoQuery> query;
  @override
  State<RelatedVideoPanel> createState() => _RelatedVideoPanelState();
}

class _RelatedVideoPanelState extends State<RelatedVideoPanel> with GridMixin {
  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 7, bottom: 100),
      sliver: ValueListenableBuilder(
        valueListenable: widget.query,
        builder: (context, query, _) => Consumer(
          builder: (context, ref, _) => _buildBody(query, ref),
        ),
      ),
    );
  }

  Widget _buildBody(RelatedVideoQuery query, WidgetRef ref) {
    final provider = relatedVideosProvider(query);
    final snapshot = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final current = notifier.captureQuery();
    return switch (snapshot.loading) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  final item = response[index];
                  return VideoCardH(
                    videoItem: item,
                    onRemove: () {
                      if (current() && identical(query, widget.query.value)) {
                        notifier.remove(item);
                      }
                    },
                  );
                },
                itemCount: response.length,
              )
            : const SliverToBoxAdapter(),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: notifier.onReload,
      ),
    };
  }
}
