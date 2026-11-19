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
          if (plPlayerController.showControls.value) {
            return const SizedBox.shrink();
          }
          final visible = switch (plPlayerController.progressType) {
            .alwaysShow => true,
            .alwaysHide => plPlayerController.isSeeking.value,
            .onlyShowFullScreen =>
              isFullScreen || plPlayerController.isSeeking.value,
            .onlyHideFullScreen =>
              !isFullScreen || plPlayerController.isSeeking.value,
          };
          if (!visible) return const SizedBox.shrink();
          return VideoProgressTrack(
            controller: plPlayerController,
            videoDetailController: videoDetailController,
            color: primary,
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
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.bottomCenter,
    children: [
      Obx(
        () => ProgressBar(
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
      ),
      if (controller.enableBlock)
        ValueListenableBuilder(
          valueListenable: videoDetailController.segmentChanges,
          builder: (context, segments, child) {
            if (segments.isEmpty) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: interactive ? 5.25 : 0.75,
              child: SegmentProgressBar(segments: segments),
            );
          },
        ),
      if (controller.showViewPoints)
        ListenableBuilder(
          listenable: Listenable.merge([
            videoDetailController.viewPoints,
            videoDetailController.showVP,
          ]),
          builder: (context, child) {
            final segments = videoDetailController.viewPointList;
            if (segments.isEmpty || !videoDetailController.showVP.value) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: interactive ? 8.75 : 4.25),
              child: ViewPointSegmentProgressBar(
                segments: segments,
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
            );
          },
        ),
      if (interactive || controller.showDmChart)
        ListenableBuilder(
          listenable: Listenable.merge([
            videoDetailController.showDmTrendChart,
            videoDetailController.dmTrend,
            videoDetailController.viewPoints,
            videoDetailController.showVP,
          ]),
          builder: (context, child) {
            if (!videoDetailController.showDmTrendChart.value) {
              return const SizedBox.shrink();
            }
            final trend = videoDetailController.dmTrend.value?.dataOrNull;
            if (trend == null || trend.isEmpty) return const SizedBox.shrink();
            final showPoints =
                videoDetailController.viewPointList.isNotEmpty &&
                videoDetailController.showVP.value;
            return DanmakuTrendChart(
              themeColor: color,
              trend: trend,
              bottom: (showPoints ? 19.25 : 4.25) + (interactive ? 4.5 : 0),
            );
          },
        ),
    ],
  );
}
