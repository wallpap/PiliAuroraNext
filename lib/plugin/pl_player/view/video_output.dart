import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/video_fit_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/video_output_resizer.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/video_output_handoff.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/video_output_paint_barrier.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/video_output_handoff.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/android_video_output_limit.dart';
import 'package:pili_aurora_next/services/windows_video_output_limit.dart';

class PlayerVideoOutput extends ChangeNotifier {
  PlayerVideoOutput({
    required this.plPlayerController,
    required this._transformationController,
  }) : videoController = plPlayerController.videoController! {
    _videoOutputPaintBarrier = VideoOutputPaintBarrier();
    _videoOutputHandoff = VideoOutputHandoff(
      waitForProtectedFrame: _videoOutputPaintBarrier.wait,
      capture: _captureVideoOutputFrame,
      waitForPaint: () => WidgetsBinding.instance.endOfFrame,
    );
    _videoOutputResizer = VideoOutputResizer(
      enabled: Platform.isWindows,
      settleDelay: const Duration(milliseconds: 100),
      apply: _applyVideoOutputSize,
      onError: (size, error, _) {
        // 失败不算已配置；后续有效事件可以重试，但不主动循环请求。
        if (Platform.isWindows) {
          Diagnostics.instance.playerLog(
            DiagnosticLogLevel.warning,
            'video.output',
            'resize.failed',
            details: {
              ..._captureVideoOutputDiagnostics(),
              'requested': {'width': size.width, 'height': size.height},
              'error': error,
            },
          );
        }
      },
    );
    if (Platform.isAndroid || Platform.isWindows) {
      // 仅在开启性能追踪时采样；页面销毁前解除，避免持有旧视口。
      _unregisterVideoDiagnostics = Diagnostics.instance.register(
        'videoViewport.${videoController.player.hashCode}.$hashCode',
        _captureVideoOutputDiagnostics,
      );
    }
    if (Platform.isWindows) {
      final sourceSizes = videoController.player.stream.videoParams
          .map(VideoOutputSizePolicy.videoDisplaySize)
          .distinct();
      _videoSizeListener = sourceSizes.listen(_onVideoOutputSourceChanged);
      scheduleMicrotask(() {
        _onVideoOutputSourceChanged(
          VideoOutputSizePolicy.videoDisplaySize(
            videoController.player.state.videoParams,
          ),
        );
      });
    }
    if (Platform.isAndroid) {
      _videoOutputFullscreenListener = plPlayerController.isFullScreen.listen(
        (_) => _logAndroidLayout(),
      );
    }

    _videoOutputHandoff.addListener(notifyListeners);
    plPlayerController.videoFramePresented.addListener(notifyListeners);
  }

  final PlPlayerController plPlayerController;
  final VideoController videoController;
  final TransformationController _transformationController;
  final _videoFrameKey = GlobalKey();
  late final VideoOutputHandoff _videoOutputHandoff;
  late final VideoOutputPaintBarrier _videoOutputPaintBarrier;
  late final VideoOutputResizer _videoOutputResizer;
  StreamSubscription? _videoSizeListener;
  StreamSubscription<bool>? _videoOutputFullscreenListener;
  void Function()? _unregisterVideoDiagnostics;
  bool _disposed = false;
  double _maxWidth = 0;
  double _maxHeight = 0;
  double _devicePixelRatio = 1;
  Orientation? _orientation;
  String? _lastAndroidLayout;

  bool get isFullScreen => plPlayerController.isFullScreen.value;
  bool get protected => _videoOutputHandoff.image != null;

  void updateLayout({
    required double width,
    required double height,
    required double devicePixelRatio,
    required Orientation orientation,
  }) {
    _maxWidth = width;
    _maxHeight = height;
    _devicePixelRatio = devicePixelRatio;
    _orientation = orientation;
    _logAndroidLayout();
  }

  bool get waitingForVideoFrame =>
      (Platform.isAndroid || Platform.isWindows) &&
      plPlayerController.dataStatus.loaded &&
      !plPlayerController.onlyPlayAudio.value &&
      plPlayerController.currentPlaybackSnapshot.capabilities.hasVideo !=
          false &&
      !plPlayerController.videoFramePresented.value;

  void _logAndroidLayout() {
    if (!Platform.isAndroid || _disposed) return;
    final state = '$isFullScreen/${plPlayerController.isPipMode}/$_orientation';
    if (state == _lastAndroidLayout) return;
    _lastAndroidLayout = state;
    if (!Diagnostics.instance.acceptsPlayer(DiagnosticLogLevel.info)) return;
    Diagnostics.instance.playerLog(
      DiagnosticLogLevel.info,
      'video.layout',
      'flutter.layout.changed',
      details: _captureVideoOutputDiagnostics(),
    );
  }

  Map<String, Object?> _captureVideoOutputDiagnostics() {
    final rect = videoController.rect.value;
    final target = _videoOutputResizer.target;
    final applied = _videoOutputResizer.applied;
    return {
      'player': 'player.${videoController.player.hashCode}',
      'outputLimitActive': Platform.isAndroid || Platform.isWindows,
      'resizePolicy': Platform.isAndroid
          ? 'fixed-device-output-limit'
          : 'display-output-limit-frame-handoff',
      'handoffActive': _videoOutputHandoff.image != null,
      'state': 'fixed-output',
      if (Platform.isAndroid)
        'deviceOutputLimit': {
          'width': AndroidVideoOutputLimit.detected?.width,
          'height': AndroidVideoOutputLimit.detected?.height,
        },
      if (Platform.isWindows)
        'deviceOutputLimit': {
          'width': WindowsVideoOutputLimit.detected?.width,
          'height': WindowsVideoOutputLimit.detected?.height,
        },
      'fullScreen': isFullScreen,
      'playing': videoController.player.state.playing,
      'positionMs': videoController.player.state.position.inMilliseconds,
      'fit': plPlayerController.videoFit.value.name,
      'viewport': {'width': _maxWidth, 'height': _maxHeight},
      'devicePixelRatio': _devicePixelRatio,
      'surfaceGeneration': _videoOutputResizer.generation,
      'textureId': videoController.id.value,
      'sourceRect': rect == null
          ? null
          : {
              'left': rect.left,
              'top': rect.top,
              'width': rect.width,
              'height': rect.height,
            },
      // 提交尺寸与期望尺寸分开记录；提交成功仍不能证明暂停帧已重绘。
      'target': target == null
          ? null
          : {'width': target.width, 'height': target.height},
      'applied': applied == null
          ? null
          : {'width': applied.width, 'height': applied.height},
      'transform': _transformationController.value.storage.toList(
        growable: false,
      ),
    };
  }

  void _logVideoOutputResize(
    String event,
    VideoOutputSize size, {
    required int generation,
    bool? accepted,
  }) {
    final diagnostics = Diagnostics.instance;
    if (!diagnostics.acceptsPlayer(DiagnosticLogLevel.info)) return;
    diagnostics.playerLog(
      DiagnosticLogLevel.info,
      'video.output',
      event,
      details: {
        ..._captureVideoOutputDiagnostics(),
        'requested': {'width': size.width, 'height': size.height},
        'requestGeneration': generation,
        // Windows 在新帧绘制完成后标记可用。
        // Android 的固定输出不进入视口 resize / handoff。
        'accepted': accepted,
      },
    );
  }

  Future<ui.Image?> _captureVideoOutputFrame() async {
    if (_disposed) return null;
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed) return null;
    final renderObject = _videoFrameKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    // 独立图片最多约 1080p；只在一次交接期间持有，不常驻复制 4K 帧。
    final ratio = math.min(
      _devicePixelRatio,
      1920 / renderObject.size.longestSide,
    );
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: ratio);
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      // 某些 renderer 不能 readback 外部纹理。透明快照不能充当保护帧。
      final center =
          ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4 + 3;
      if (pixels == null || pixels.getUint8(center) == 0) {
        image.dispose();
        return null;
      }
      return image;
    } catch (error) {
      image?.dispose();
      Diagnostics.instance.playerLog(
        DiagnosticLogLevel.warning,
        'video.output',
        'handoff.capture.failed',
        details: {'error': error},
      );
      return null;
    }
  }

  void _onVideoOutputSourceChanged(VideoOutputSize? sourceSize) {
    if (!Platform.isWindows || _disposed) return;
    _videoOutputHandoff.invalidate();
    _videoOutputPaintBarrier.cancel();
    _videoOutputResizer.invalidate();
    final size = VideoOutputSizePolicy.fitWithinLimit(
      source: sourceSize,
      limit: WindowsVideoOutputLimit.detected,
    );
    if (size == null) return;
    _videoOutputResizer.request(size);
  }

  Future<bool> _applyVideoOutputSize(
    VideoOutputSize size,
    bool Function() isCurrent,
  ) async {
    if (Platform.isAndroid) return false;
    if (!Platform.isWindows) {
      await videoController.setSize(width: size.width, height: size.height);
      return true;
    }
    final generation = _videoOutputResizer.generation;
    _logVideoOutputResize('resize.requested', size, generation: generation);
    final player = videoController.player;
    if (player.current.isEmpty) return false;
    final media = player.current.first;
    final state = player.state;
    final previousSize =
        _videoOutputResizer.applied ??
        (width: state.width, height: state.height);
    bool current() =>
        !_disposed &&
        isCurrent() &&
        !player.disposed &&
        player.current.isNotEmpty &&
        identical(player.current.first, media);
    final rect = videoController.rect.value;
    if (_videoOutputHandoff.image == null &&
        rect?.width == size.width &&
        rect?.height == size.height) {
      // 暂停加载已配置最终输出；沿用有效纹理，不再为相同尺寸截取保护图。
      if (!current() || _videoOutputResizer.target != size) return false;
      await videoController.setSize(width: size.width, height: size.height);
      final accepted = current();
      if (!_disposed) {
        _logVideoOutputResize(
          'resize.completed',
          size,
          generation: generation,
          accepted: accepted,
        );
      }
      return accepted;
    }
    final accepted = await _videoOutputHandoff.run(
      isCurrent: current,
      canStart: () => Platform.isWindows && _videoOutputResizer.target == size,
      submit: (canStart) async {
        if (!canStart()) return false;
        // Windows completion now means a replacement frame was rendered and
        // marked available, rather than only queued on its worker thread.
        await videoController.setSize(width: size.width, height: size.height);
        return true;
      },
      recover: previousSize.width <= 0 || previousSize.height <= 0
          ? null
          : () async {
              if (!current()) return false;
              await videoController.setSize(
                width: previousSize.width,
                height: previousSize.height,
              );
              return true;
            },
    );
    if (!_disposed) {
      _logVideoOutputResize(
        'resize.completed',
        size,
        generation: generation,
        accepted: accepted,
      );
    }
    return accepted;
  }

  void notifyDesktopFramePresented() {
    final loadId = plPlayerController.currentPlaybackSnapshot.loadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || loadId == null || protected) return;
      final size = _videoFrameKey.currentContext?.size;
      final hasVideo =
          plPlayerController.currentPlaybackSnapshot.capabilities.hasVideo !=
          false;
      if (!hasVideo || (size != null && !size.isEmpty)) {
        unawaited(plPlayerController.notifyDesktopFramePresented(loadId));
      }
    });
  }

  Widget buildFrame({required Color fill, required VideoFitType fit}) {
    final video = SimpleVideo(
      controller: videoController,
      fill: fill,
      aspectRatio: fit.aspectRatio,
    );
    return Platform.isAndroid || Platform.isWindows
        ? VideoOutputHandoffView(
            handoff: _videoOutputHandoff,
            frameKey: _videoFrameKey,
            child: video,
          )
        : video;
  }

  @override
  void dispose() {
    _disposed = true;
    _unregisterVideoDiagnostics?.call();
    _videoSizeListener?.cancel();
    _videoOutputFullscreenListener?.cancel();
    plPlayerController.videoFramePresented.removeListener(notifyListeners);
    _videoOutputHandoff.removeListener(notifyListeners);
    _videoOutputResizer.dispose();
    _videoOutputHandoff.dispose();
    _videoOutputPaintBarrier.dispose();
    super.dispose();
  }
}
