import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:pili_aurora_next/core/time/duration_format.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_progress.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_time.dart';

VideoDetailController? mountedVideoPage(
  PlPlayerController? player, {
  int? cid,
}) {
  VideoDetailController? page;
  void visit(Element element) {
    if (element.widget
        case VideoProgressTrack(
          :final controller,
          :final videoDetailController,
        )
        when identical(controller, player) &&
            (cid == null || videoDetailController.cid.value == cid)) {
      page = videoDetailController;
    }
    if (page == null) element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return page;
}

Future<Map<String, Object?>> observeReplayProgress(
  PlPlayerController player,
  VideoDetailController page,
) async {
  final steps = <String, Object?>{};
  final durationWatch = Stopwatch()..start();
  late Duration length;
  while (true) {
    final actual = player.videoPlayerController?.state.duration;
    if (actual != null &&
        actual >= const Duration(seconds: 5) &&
        actual.inSeconds == player.duration.value) {
      length = actual;
      break;
    }
    if (durationWatch.elapsed >= const Duration(seconds: 8)) {
      return {
        'passed': false,
        'reason': 'duration not confirmed',
        'actualMs': actual?.inMilliseconds,
        'projectedMs': player.durationInMilliseconds,
      };
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<bool> observe(
    String name, {
    required PlaybackPhase phase,
    required int minimum,
    required int maximum,
    int? previousLoad,
  }) async {
    final watch = Stopwatch()..start();
    do {
      VideoTime? time;
      ProgressBar? track;
      RenderProgressBar? rendered;
      void visit(Element element) {
        if (element.widget case final VideoTime widget) time = widget;
        if (element.widget case final ProgressBar widget
            when widget.onDragStart != null) {
          track = widget;
          rendered = element.findRenderObject() as RenderProgressBar?;
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final snapshot = player.currentPlaybackSnapshot;
      final position = player.position.value;
      final total = player.duration.value;
      final passed =
          snapshot.phase == phase &&
          snapshot.loadId != null &&
          (previousLoad == null || snapshot.loadId != previousLoad) &&
          position >= minimum &&
          position <= maximum &&
          track?.progress == position &&
          rendered?.progress == position &&
          track?.total == total &&
          time?.position == DurationUtils.formatDuration(position) &&
          time?.duration == DurationUtils.formatDuration(total);
      steps[name] = {
        'passed': passed,
        'phase': snapshot.phase.name,
        'load': snapshot.loadId,
        'minimum': minimum,
        'maximum': maximum,
        'position': position,
        'duration': total,
        'track': track?.progress,
        'trackTotal': track?.total,
        'rendered': rendered?.progress,
        'time': time?.position,
        'timeTotal': time?.duration,
      };
      if (passed) return true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    } while (watch.elapsed < const Duration(seconds: 8));
    return false;
  }

  await player.seekTo(length - const Duration(seconds: 1));
  await player.play(hideControls: false);
  final ended = await observe(
    'ended',
    phase: PlaybackPhase.ended,
    minimum: length.inSeconds - 2,
    maximum: length.inSeconds,
  );
  final endedLoad = player.currentPlaybackSnapshot.loadId;
  if (!ended) return {'passed': false, 'steps': steps};

  await page.playerInit(autoplay: false);
  player.controls = true;
  final reset = await observe(
    'reopened',
    phase: PlaybackPhase.ready,
    minimum: 0,
    maximum: 0,
    previousLoad: endedLoad,
  );
  if (!reset) return {'passed': false, 'steps': steps};

  await player.play(hideControls: false);
  final advanced = await observe(
    'advancing',
    phase: PlaybackPhase.ready,
    minimum: 1,
    maximum: 3,
    previousLoad: endedLoad,
  );
  return {'passed': advanced, 'steps': steps};
}
