import 'dart:async';

import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_chart.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/services/feedback/feed_back.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';

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

class VideoProgressTrack extends StatefulWidget {
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

  @override
  State<VideoProgressTrack> createState() => _VideoProgressTrackState();
}

class _VideoProgressTrackState extends State<VideoProgressTrack> {
  PlPlayerController get controller => widget.controller;
  VideoDetailController get videoDetailController =>
      widget.videoDetailController;
  Color get color => widget.color;
  bool get interactive => widget.interactive;
  Object? _drag;
  bool _dragStarted = false;
  (PlPlayerController, int, bool)? _trackIdentity;

  void onDragStart(ThumbDragDetails duration) {
    _dragStarted = true;
    _drag = controller.onSeekStart(duration.seconds);
    if (_drag != null) feedBack();
  }

  void onDragUpdate(ThumbDragDetails duration) =>
      controller.onSeekUpdate(_drag, duration.seconds);

  void onSeek(int milliseconds) {
    final target = Duration(milliseconds: milliseconds);
    if (!_dragStarted) {
      unawaited(controller.seekTo(target, isSeek: false));
      return;
    }
    final drag = _takeDrag();
    controller.onSeekEnd(drag, target: target);
  }

  Object? _takeDrag() {
    final drag = _drag;
    _drag = null;
    _dragStarted = false;
    return drag;
  }

  void onDragCancel() => controller.onSeekEnd(_takeDrag());

  @override
  void dispose() {
    final drag = _takeDrag();
    final player = controller;
    if (drag != null) scheduleMicrotask(() => player.onSeekEnd(drag));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.bottomCenter,
    children: [
      Obx(
        () {
          final identity = (
            controller,
            controller.seekDragEpoch,
            interactive,
          );
          if (_trackIdentity != identity) {
            final previous = _trackIdentity;
            final drag = _takeDrag();
            if (previous != null && drag != null) {
              scheduleMicrotask(() => previous.$1.onSeekEnd(drag));
            }
            _trackIdentity = identity;
          }
          return ProgressBar(
            key: ValueKey(identity),
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
            onDragCancel: interactive ? onDragCancel : null,
            onSeek: interactive ? onSeek : null,
          );
        },
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
