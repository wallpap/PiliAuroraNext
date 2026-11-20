import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/image/image_save.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/marquee.dart';
import 'package:pili_aurora_next/common/widgets/stat/stat.dart';
import 'package:pili_aurora_next/features/playback/application/music_queries.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/widgets/badge_type.dart';
import 'package:pili_aurora_next/common/widgets/stat/stat_type.dart';
import 'package:pili_aurora_next/features/playback/domain/music/bgm_recommend_list.dart';
import 'package:pili_aurora_next/core/time/duration_format.dart';
import 'package:pili_aurora_next/router/navigation_request.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:material_ui/material_ui.dart';

class MusicVideoCardH extends StatelessWidget {
  final BgmRecommend videoItem;

  const MusicVideoCardH({
    super.key,
    required this.videoItem,
  });

  Future<void> _openVideo(BuildContext context) async {
    final request = NavigationRequest();
    bool current() => context.mounted && request.isCurrent;
    try {
      final result = await MusicQueries.openVideo(videoItem, current);
      if (!current()) return;
      if (result case Error error) {
        error.toast();
        return;
      }
      if (!result.isSuccess) return;
      final (:bvid, :cid, :dimension) = result.data;
      PageUtils.toVideoPage(
        bvid: bvid,
        cid: cid,
        cover: videoItem.cover,
        title: videoItem.title,
        dimension: dimension,
      );
    } catch (error, stackTrace) {
      logger.w('打开音乐视频失败', error: error.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('视频获取失败，请重试');
    } finally {
      await request.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _openVideo(context),
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    double maxWidth = boxConstraints.maxWidth;
                    double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: videoItem.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                        PBadge(
                          text: DurationUtils.formatDuration(
                            videoItem.duration,
                          ),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              content(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              videoItem.title ?? '未命名视频',
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: videoItem.play,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: videoItem.danmu,
              ),
            ],
          ),
          const SizedBox(height: 3),
          NormalMarquee(
            velocity: 25,
            spacing: 30,
            child: Row(
              spacing: 8,
              children: [
                if (videoItem.labelList case final labelList?)
                  for (final label in labelList)
                    PBadge(
                      text: label.name,
                      isStack: false,
                      size: PBadgeSize.small,
                      type: PBadgeType.secondary,
                    ),
                Text(
                  videoItem.upNickName ?? '未知创作者',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
