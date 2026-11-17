import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_chart.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';

class CompactVideoProgress extends StatelessWidget {
  const CompactVideoProgress({
    super.key,
    required this.plPlayerController,
    required this.videoDetailController,
    required this.isFullScreen,
  });
  final PlPlayerController plPlayerController;
  final VideoDetailController videoDetailController;
  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = isFullScreen && colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    return Positioned(
      bottom: -2.2,
      left: 0,
      right: 0,
      child: Obx(
        () {
          final showControls = plPlayerController.showControls.value;
          final bool offstage;
          switch (plPlayerController.progressType) {
            case .alwaysShow:
              offstage = showControls;
            case .alwaysHide:
              if (!plPlayerController.isSeeking.value) {
                return const SizedBox.shrink();
              }
              offstage = showControls;
            case .onlyShowFullScreen:
              offstage =
                  showControls ||
                  (!isFullScreen && !plPlayerController.isSeeking.value);
            case .onlyHideFullScreen:
              offstage =
                  showControls ||
                  (isFullScreen && !plPlayerController.isSeeking.value);
          }
          return Offstage(
            offstage: offstage,
            child: VideoProgressTrack(
              controller: plPlayerController,
              videoDetailController: videoDetailController,
              color: primary,
            ),
          );
        },
      ),
    );
  }
}

class VideoProgressTrack extends StatelessWidget {
  const VideoProgressTrack({
    super.key,
    required this.controller,
    required this.videoDetailController,
    required this.color,
    this.interactive = false,
  });
  final PlPlayerController controller;
  final VideoDetailController videoDetailController;
  final Color color;
  final bool interactive;

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onSeekStart(duration.seconds);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    if (!controller.isFileSource && controller.showSeekPreview) {
      controller.updatePreviewIndex(duration.seconds);
    }
    controller.seekPosition.value = duration.seconds;
  }

  void onSeek(int milliseconds) {
    controller
      ..position.value = milliseconds ~/ 1000
      ..onSeekEnd()
      ..seekTo(Duration(milliseconds: milliseconds), isSeek: false);
  }

  @override
  Widget build(BuildContext context) => Obx(
    () => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        ProgressBar(
          progress: controller.progress,
          buffered: controller.buffered.value,
          total: controller.duration.value,
          progressBarColor: color,
          baseBarColor: const Color(0x33FFFFFF),
          bufferedBarColor: color.withValues(alpha: 0.4),
          thumbColor: color,
          thumbGlowColor: color.withAlpha(80),
          barHeight: 3.5,
          thumbRadius: interactive ? 7 : 2.5,
          thumbGlowRadius: interactive ? 25 : 30,
          onDragStart: interactive ? onDragStart : null,
          onDragUpdate: interactive ? onDragUpdate : null,
          onSeek: interactive ? onSeek : null,
        ),
        if (controller.enableBlock &&
            videoDetailController.segmentProgressList.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: interactive ? 5.25 : 0.75,
            child: SegmentProgressBar(
              segments: videoDetailController.segmentProgressList,
            ),
          ),
        if (controller.showViewPoints &&
            videoDetailController.viewPointList.isNotEmpty &&
            videoDetailController.showVP.value)
          Padding(
            padding: EdgeInsets.only(bottom: interactive ? 8.75 : 4.25),
            child: ViewPointSegmentProgressBar(
              segments: videoDetailController.viewPointList,
              onSeek:
                  (interactive
                      ? PlatformUtils.isDesktop
                      : PlatformUtils.isMobile)
                  ? (position) {
                      if (interactive || !controller.controlsLock.value) {
                        controller.seekTo(position, isSeek: false);
                      }
                    }
                  : null,
            ),
          ),
        if ((interactive || controller.showDmChart) &&
            videoDetailController.showDmTrendChart.value)
          if (videoDetailController.dmTrend.value?.dataOrNull case final list?)
            buildDmChart(
              color,
              list,
              videoDetailController,
              interactive ? 4.5 : 0,
            ),
      ],
    ),
  );
}
