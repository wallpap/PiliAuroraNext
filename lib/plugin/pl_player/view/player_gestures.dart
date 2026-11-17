import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:pili_aurora_next/common/widgets/gesture/immediate_tap_gesture_recognizer.dart';
import 'package:pili_aurora_next/common/widgets/gesture/mouse_interactive_viewer.dart';
import 'package:pili_aurora_next/common/widgets/gesture/player_gesture_recognizer.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/double_tap_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/gesture_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_actions.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/scale_restore.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:pili_aurora_next/utils/volume_utils.dart';

class PlayerGestures {
  PlayerGestures({
    required this.plPlayerController,
    required this.danmakuActions,
    required this.context,
  }) {
    if (PlatformUtils.isMobile) {
      Future.microtask(() {
        if (_disposed) return;
        try {
          FlutterVolumeController.updateShowSystemUI(true);
          _getCurrVolume();
          FlutterVolumeController.addListener(
            _onVolumeChanged,
            // The plugin defaults to ambient and overwrites AVAudioSession.
            // Keep media playback audible regardless of listener/mpv init order.
            category: AudioSessionCategory.playback,
            emitOnStart: false,
          );
        } catch (_) {}

        try {
          if (plPlayerController.setSystemBrightness) {
            _getSystemBrightness();
            _brightnessListener = ScreenBrightnessPlatform
                .instance
                .onSystemScreenBrightnessChanged
                .listen(_onBrightnessChanged);
          } else {
            _getAppBrightness();
            _brightnessListener = ScreenBrightnessPlatform
                .instance
                .onApplicationScreenBrightnessChanged
                .listen(_onBrightnessChanged);
          }
        } catch (_) {}
      });
    }

    if (plPlayerController.enableTapDm) {
      _tapGestureRecognizer = ImmediateTapGestureRecognizer(
        onTapDown: plPlayerController.enableShowDanmakuAdaptive.value
            ? _onTapDown
            : null,
        onTapUp: _onTapUp,
        onTapCancel: danmakuActions.clear,
      );

      _danmakuListener = plPlayerController.enableShowDanmakuAdaptive.listen((
        value,
      ) {
        if (!value) danmakuActions.clear();
        _tapGestureRecognizer.onTapDown = value ? _onTapDown : null;
      });
    } else {
      _tapGestureRecognizer = ImmediateTapGestureRecognizer(onTapUp: _onTapUp);
    }

    _doubleTapGestureRecognizer = DoubleTapGestureRecognizer()
      ..onDoubleTapDown = _onDoubleTapDown;

    _scaleGestureRecognizer = PlayerScaleGestureRecognizer(
      debugOwner: this,
      dragStartBehavior: .start,
      allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
      trackpadScrollToScaleFactor: const Offset(
        0,
        -1 / kDefaultMouseScrollToScaleFactor,
      ),
      trackpadScrollCausesScale: false,
    );
  }

  final PlPlayerController plPlayerController;
  final PlayerDanmakuActions danmakuActions;
  final BuildContext Function() context;
  final _videoKey = GlobalKey();
  final transformationController = TransformationController();
  bool _disposed = false;
  double _maxWidth = 0;
  double _maxHeight = 0;
  ColorScheme get _colorScheme => ColorScheme.of(context());
  bool get _isFullScreen => plPlayerController.isFullScreen.value;

  final RxDouble _brightnessValue = 0.0.obs;
  final RxBool _brightnessIndicator = false.obs;
  Timer? _brightnessTimer;

  late final RxBool _showRestoreScaleBtn = false.obs;

  GestureType? _gestureType;
  Offset? _initialFocalPoint;

  StreamSubscription? _brightnessListener;
  void _onBrightnessChanged(double value) {
    if (!_disposed && _gestureType != .left) {
      _brightnessValue.value = value;
    }
  }

  void _getSystemBrightness() {
    ScreenBrightnessPlatform.instance.system.then((res) {
      if (!_disposed) {
        _brightnessValue.value = res;
      }
    });
  }

  void _getAppBrightness() {
    ScreenBrightnessPlatform.instance.application.then((res) {
      if (!_disposed) {
        _brightnessValue.value = res;
      }
    });
  }

  void _onVolumeChanged(double value) {
    if (!_disposed && !plPlayerController.volumeInterceptEventStream) {
      plPlayerController.volume.value = roundVolumeRatio(value);
    }
  }

  void _getCurrVolume() {
    FlutterVolumeController.getVolume().then((res) {
      if (!_disposed) {
        plPlayerController.volume.value = roundVolumeRatio(res!);
      }
    });
  }

  Future<void> _setBrightness(double value) async {
    _brightnessValue.value = value;
    try {
      if (plPlayerController.setSystemBrightness) {
        await ScreenBrightnessPlatform.instance.setSystemScreenBrightness(
          value,
        );
      } else {
        await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
          value,
        );
      }
    } catch (_) {}
    if (_disposed) return;
    _brightnessIndicator.value = true;
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_disposed) {
        _brightnessIndicator.value = false;
      }
    });
    plPlayerController.brightness.value = value;
  }

  double? _gestureVolume;
  final _scrollVolume = VolumeScrollAdjustment();

  void _onPanStart(ScaleStartDetails details) {
    _gestureVolume = null;
    _gestureType = null;
    _initialFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(double scale) {
    _showRestoreScaleBtn.value = scale != 1.0;
  }

  void _onHorizontalDragStart() {
    plPlayerController.onSeekStart(plPlayerController.position.value);
  }

  void _onHorizontalDragUpdate(double dx) {
    final curPos =
        plPlayerController.seekToPos?.inMilliseconds ??
        plPlayerController.seekPosition.value * 1000;
    final posDelta = (plPlayerController.sliderScale * dx / _maxWidth).round();
    final newPos = (curPos + posDelta).clamp(
      0,
      plPlayerController.durationInMilliseconds,
    );
    final seconds = newPos ~/ 1000;
    plPlayerController
      ..seekToPos = Duration(milliseconds: newPos)
      ..seekPosition.value = seconds;
    if (!plPlayerController.isFileSource &&
        plPlayerController.showSeekPreview) {
      plPlayerController.updatePreviewIndex(seconds);
    }
  }

  void _onHorizontalDragEnd() {
    if (plPlayerController.seekToPos case final seekToPos?) {
      feedBack();
      plPlayerController
        ..position.value = seekToPos.inSeconds
        ..seekTo(seekToPos, isSeek: false)
        ..seekToPos = null;
    } else {
      plPlayerController.position.value =
          plPlayerController.videoPlayerController?.state.position.inSeconds ??
          0;
    }
    plPlayerController.onSeekEnd();
  }

  void _onPanUpdate(ScaleUpdateDetails details) {
    if (_gestureType == null) {
      final cumulativeDelta = details.localFocalPoint - _initialFocalPoint!;
      if (cumulativeDelta.distanceSquared < 1) return;
      final dx = cumulativeDelta.dx.abs();
      final dy = cumulativeDelta.dy.abs();
      if (dx > 3 * dy) {
        _onHorizontalDragStart();
        _gestureType = .horizontal;
      } else if (dy > 3 * dx) {
        if (!plPlayerController.enableSlideVolumeBrightness &&
            !plPlayerController.enableSlideFS) {
          return;
        }

        final double tapPosition = details.localFocalPoint.dx;
        final double sectionWidth = _maxWidth / 3;
        if (tapPosition < sectionWidth) {
          if (!plPlayerController.enableSlideVolumeBrightness) {
            return;
          }
          // 左边区域
          if (PlatformUtils.isDesktop) {
            _gestureType = .right;
          } else {
            _gestureType = .left;
          }
        } else if (tapPosition < sectionWidth * 2) {
          if (!plPlayerController.enableSlideFS) {
            return;
          }
          // 全屏
          _gestureType = .center;
        } else {
          if (!plPlayerController.enableSlideVolumeBrightness) {
            return;
          }
          // 右边区域
          _gestureType = .right;
        }
      }
      return;
    }

    Offset delta = details.focalPointDelta;

    if (_gestureType == .horizontal) {
      // live模式下禁用
      if (plPlayerController.isLive) return;

      final height = _maxHeight * 0.125;
      if (details.localFocalPoint.dy <= height &&
          (details.localFocalPoint.dx >= _maxWidth * 0.875 ||
              details.localFocalPoint.dx <= _maxWidth * 0.125)) {
        if (!plPlayerController.hasToasted) {
          plPlayerController
            ..seekToPos = null
            ..hasToasted = true;
          if (plPlayerController.showSeekPreview) {
            plPlayerController.showPreview.value = false;
          }
          SmartDialog.showAttach(
            targetContext: context(),
            alignment: .center,
            usePenetrate: true,
            animationType: .fade,
            maskColor: Colors.transparent,
            displayTime: const Duration(milliseconds: 1500),
            animationTime: const Duration(milliseconds: 200),
            builder: (context) => Container(
              padding: const .symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: const .all(.circular(6)),
                color: _colorScheme.secondaryContainer,
              ),
              child: Text(
                '松开手指，取消进退',
                style: TextStyle(color: _colorScheme.onSecondaryContainer),
              ),
            ),
          );
        }
        return;
      } else if (plPlayerController.hasToasted) {
        plPlayerController.hasToasted = false;
      }

      _onHorizontalDragUpdate(delta.dx);
    } else if (_gestureType == .left) {
      // 左边区域 👈
      final double level = _maxHeight * 3;
      final double brightness = (_brightnessValue.value - delta.dy / level)
          .clamp(0.0, 1.0);
      _setBrightness(brightness);
    } else if (_gestureType == .center) {
      // 全屏
      const double threshold = 2.5; // 滑动阈值
      double cumulativeDy = details.localFocalPoint.dy - _initialFocalPoint!.dy;

      void fullScreenTrigger(bool status) {
        plPlayerController.triggerFullScreen(status: status);
      }

      if (cumulativeDy > threshold) {
        _gestureType = .center_down;
        if (_isFullScreen ^ plPlayerController.fullScreenGestureReverse) {
          fullScreenTrigger(
            plPlayerController.fullScreenGestureReverse,
          );
        }
      } else if (cumulativeDy < -threshold) {
        _gestureType = .center_up;
        if (!_isFullScreen ^ plPlayerController.fullScreenGestureReverse) {
          fullScreenTrigger(
            !plPlayerController.fullScreenGestureReverse,
          );
        }
      }
    } else if (_gestureType == .right) {
      // 右边区域
      final double level = _maxHeight * 0.5;
      _gestureVolume = clampDouble(
        (_gestureVolume ?? plPlayerController.volume.value) - delta.dy / level,
        0,
        1,
      );
      ActionThrottle.run(
        'setVolume',
        const Duration(milliseconds: 20),
        () {
          final double volume = clampDouble(
            _gestureVolume!,
            0.0,
            plPlayerController.maxVolume,
          );
          plPlayerController.setVolume(volume);
        },
      );
    }
  }

  void _onPanEnd(ScaleEndDetails details) {
    _gestureVolume = null;
    if (_gestureType == .horizontal) {
      _onHorizontalDragEnd();
    }
    _initialFocalPoint = null;
    _gestureType = null;
  }

  void _onDoubleTapDownMobile(TapDownDetails details) {
    if (plPlayerController.isLive || plPlayerController.controlsLock.value) {
      return;
    }
    final double tapPosition = details.localPosition.dx;
    final double sectionWidth = _maxWidth / 4;
    DoubleTapType type;
    if (tapPosition < sectionWidth) {
      type = DoubleTapType.left;
    } else if (tapPosition < sectionWidth * 3) {
      type = DoubleTapType.center;
    } else {
      type = DoubleTapType.right;
    }
    plPlayerController.doubleTapFuc(type);
  }

  void _onTapUp(TapUpDetails details) {
    switch (details.kind) {
      case ui.PointerDeviceKind.mouse when PlatformUtils.isDesktop:
        plPlayerController.onDoubleTapCenter();
      default:
        if (!danmakuActions.showAt(details.localPosition)) {
          plPlayerController.controls = !plPlayerController.showControls.value;
        }
    }
  }

  void _onTapDown(TapDownDetails details) =>
      danmakuActions.selectAt(details.localPosition);

  void _onDoubleTapDown(TapDownDetails details) {
    switch (details.kind) {
      case ui.PointerDeviceKind.mouse when PlatformUtils.isDesktop:
        plPlayerController.triggerFullScreen(status: !_isFullScreen);
      default:
        _onDoubleTapDownMobile(details);
    }
  }

  LongPressGestureRecognizer? _longPressRecognizer;
  LongPressGestureRecognizer get longPressRecognizer => _longPressRecognizer ??=
      LongPressGestureRecognizer(
          duration: plPlayerController.enableTapDm
              ? const Duration(milliseconds: 300)
              : null,
        )
        ..onLongPressStart = ((_) =>
            plPlayerController.setLongPressStatus(true))
        ..onLongPressEnd = ((_) => plPlayerController.setLongPressStatus(false))
        ..onLongPressCancel = (() =>
            plPlayerController.setLongPressStatus(false));
  late final ImmediateTapGestureRecognizer _tapGestureRecognizer;
  late final DoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final PlayerScaleGestureRecognizer _scaleGestureRecognizer;

  StreamSubscription<bool>? _danmakuListener;

  static const _kOffsetThreshold = 25.0;
  bool _isPositionAllowed(Offset offset) {
    if (offset.dx < _kOffsetThreshold ||
        offset.dy < _kOffsetThreshold ||
        offset.dx > _maxWidth - _kOffsetThreshold ||
        offset.dy > _maxHeight - _kOffsetThreshold) {
      return false;
    }
    return true;
  }

  /// 鼠标中键/右键全屏切换的挂起项：(进入全屏, 应用内全屏)。
  /// 在鼠标按下时启动原生全屏过渡会与本次点击重叠，窗口可能卡在半过渡状态
  /// 导致鼠标事件失效，因此延后到抬起后执行。
  (bool, bool)? _pendingFullScreenToggle;

  void _onPointerDown(PointerDownEvent event) {
    if (PlatformUtils.isDesktop) {
      final buttons = event.buttons;
      final isSecondaryBtn = buttons == kSecondaryMouseButton;
      if (isSecondaryBtn || buttons == kMiddleMouseButton) {
        _pendingFullScreenToggle = (!_isFullScreen, isSecondaryBtn);
        return;
      }
    }

    final controlsUnlock = !plPlayerController.controlsLock.value;
    if (PlatformUtils.isMobile) {
      _tapGestureRecognizer.addPointer(event);
      if (controlsUnlock) {
        if (!plPlayerController.isLive) {
          _doubleTapGestureRecognizer.addPointer(event);
          longPressRecognizer.addPointer(event);
        }
        _scaleGestureRecognizer
          ..isPosAllowed = _isPositionAllowed(event.localPosition)
          ..addPointer(event);
      }
    } else if (controlsUnlock) {
      if (plPlayerController.isLive) {
        _doubleTapGestureRecognizer.addPointer(event);
      } else {
        _tapGestureRecognizer.addPointer(event);
        _doubleTapGestureRecognizer.addPointer(event);
        longPressRecognizer.addPointer(event);
      }
      _scaleGestureRecognizer.addPointer(event);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final pending = _pendingFullScreenToggle;
    if (pending == null || event.buttons != 0) {
      return;
    }
    _pendingFullScreenToggle = null;
    if (_isFullScreen && plPlayerController.controlsLock.value) {
      plPlayerController
        ..controlsLock.value = false
        ..showControls.value = false;
    }
    plPlayerController.triggerFullScreen(
      status: pending.$1,
      inAppFullScreen: pending.$2,
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pendingFullScreenToggle = null;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (plPlayerController.controlsLock.value) return;
    if (_gestureType == null) {
      final pan = event.pan;
      if (pan.distanceSquared < 1) return;
      final dx = pan.dx.abs();
      final dy = pan.dy.abs();
      if (dx > 3 * dy) {
        _onHorizontalDragStart();
        _gestureType = .horizontal;
      } else if (dy > 3 * dx) {
        _gestureType = .right;
      }
      return;
    }

    if (_gestureType == .horizontal) {
      if (plPlayerController.isLive) return;

      _onHorizontalDragUpdate(event.localPanDelta.dx);
    } else if (_gestureType == .right) {
      if (!plPlayerController.enableSlideVolumeBrightness) {
        return;
      }

      final double level = _maxHeight * 0.5;
      _gestureVolume = clampDouble(
        (_gestureVolume ?? plPlayerController.volume.value) -
            event.localPanDelta.dy / level,
        0,
        1,
      );
      ActionThrottle.run(
        'setVolume',
        const Duration(milliseconds: 20),
        () {
          final double volume = clampDouble(
            _gestureVolume!,
            0.0,
            plPlayerController.maxVolume,
          );
          plPlayerController.setVolume(volume);
        },
      );
    }
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _gestureVolume = null;
    if (_gestureType == .horizontal) {
      _onHorizontalDragEnd();
    }
    _gestureType = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final volume = _scrollVolume.apply(
        plPlayerController.volume.value,
        event.scrollDelta.dy,
      );
      plPlayerController.setVolume(volume);
    }
  }

  Widget buildSurface({
    required double width,
    required double height,
    required Widget child,
  }) {
    _maxWidth = width;
    _maxHeight = height;
    return MouseInteractiveViewer(
      scaleEnabled: !plPlayerController.controlsLock.value,
      pointerSignalFallback: _onPointerSignal,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onScaleUpdate: _onScaleUpdate,
      scaleGestureRecognizer: _scaleGestureRecognizer,
      panEnabled: false,
      minScale: plPlayerController.enableShrinkVideoSize ? 0.75 : 1,
      maxScale: 2.0,
      boundaryMargin: plPlayerController.enableShrinkVideoSize
          ? const .all(double.infinity)
          : .zero,
      panAxis: .aligned,
      transformationController: transformationController,
      childKey: _videoKey,
      child: RepaintBoundary(key: _videoKey, child: child),
    );
  }

  Widget buildBrightnessIndicator() => IgnorePointer(
    ignoring: true,
    child: Align(
      alignment: Alignment.center,
      child: Obx(
        () => AnimatedOpacity(
          curve: Curves.easeInOut,
          opacity: _brightnessIndicator.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            decoration: const BoxDecoration(
              color: Color(0x88000000),
              borderRadius: BorderRadius.all(Radius.circular(64)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  _brightnessValue.value < 1.0 / 3.0
                      ? Icons.brightness_low
                      : _brightnessValue.value < 2.0 / 3.0
                      ? Icons.brightness_medium
                      : Icons.brightness_high,
                  color: Colors.white,
                  size: 18.0,
                ),
                const SizedBox(width: 2.0),
                Text(
                  '${(_brightnessValue.value * 100.0).round()}%',
                  style: const TextStyle(
                    fontSize: 13.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget buildRestoreButton() => PlayerScaleRestore(
    plPlayerController: plPlayerController,
    transformationController: transformationController,
    showRestore: _showRestoreScaleBtn,
  );

  void dispose() {
    _disposed = true;
    _danmakuListener?.cancel();
    _tapGestureRecognizer.dispose();
    _longPressRecognizer?.dispose();
    _doubleTapGestureRecognizer.dispose();
    _scaleGestureRecognizer.dispose();
    _brightnessListener?.cancel();
    _brightnessTimer?.cancel();
    transformationController.dispose();
    if (PlatformUtils.isMobile) FlutterVolumeController.removeListener();
  }
}
