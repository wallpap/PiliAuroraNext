import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/playback/application/music_queries.dart';
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_recommend_list.dart';
import 'package:pili_aurora_next/pages/music/widget/music_video_card_h.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MusicRecommendPage extends ConsumerStatefulWidget {
  const MusicRecommendPage({super.key});

  @override
  ConsumerState<MusicRecommendPage> createState() => _MusicRecommendPageState();
}

class _MusicRecommendPageState extends ConsumerState<MusicRecommendPage>
    with GridMixin {
  late final _arguments = Get.arguments as MusicRecommendArgs;
  late final _provider = musicRecommendationsProvider(_arguments.id);

  Future<void> _reload() async {
    ref.invalidate(_provider);
    try {
      await ref.read(_provider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(_provider);
    final items = !snapshot.isLoading && !snapshot.hasError
        ? snapshot.value
        : null;
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return Material(
      color: theme.colorScheme.surface,
      child: refreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(theme, padding, items?.length),
            SliverPadding(
              padding: EdgeInsets.only(
                top: 7,
                left: padding.left,
                right: padding.right,
                bottom: padding.bottom + 100,
              ),
              sliver: snapshot.when(
                skipLoadingOnRefresh: false,
                loading: () => gridSkeleton,
                error: (error, _) =>
                    HttpError(errMsg: error.toString(), onReload: _reload),
                data: _buildBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<BgmRecommend>? response) =>
      response == null || response.isEmpty
      ? HttpError(onReload: _reload)
      : SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemBuilder: (context, index) =>
              MusicVideoCardH(videoItem: response[index]),
          itemCount: response.length,
        );

  Widget _buildAppBar(ThemeData theme, EdgeInsets padding, int? count) {
    final info = _arguments.item;
    return SliverAppBar(
      pinned: true,
      title: Row(
        spacing: 12,
        children: [
          NetworkImgLayer(
            width: 40,
            height: 40,
            src: info.mvCover,
            type: ImageType.avatar,
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.musicTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              if (count != null)
                Text(
                  '共$count条视频',
                  style: theme.textTheme.labelMedium,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
