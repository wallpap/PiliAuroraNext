import 'dart:async';
import 'dart:io';

import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_actions.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/player_gestures.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/player_indicators.dart';

import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/live_room/widgets/bottom_control.dart'
    as live_bottom;
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/audio_recovery.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/app_bar_ani.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/player_loading.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/player_subtitle_view.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/seek_indicator.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/bottom_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/common_btn.dart';
import 'package:pili_aurora_next/utils/android/bindings.g.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'package:pili_aurora_next/plugin/pl_player/view/video_progress.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/seek_preview.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_controls.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/webp_capture.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_output.dart';

class PLVideoPlayer extends StatefulWidget {
  const PLVideoPlayer({
    required this.maxWidth,
    required this.maxHeight,
    required this.plPlayerController,
    this.videoDetailController,
    this.introController,
    required this.headerControl,
    this.bottomControl,
    this.onRetry,
    this.danmuWidget,
    this.showEpisodes,
    this.showViewPoints,
    this.fill = Colors.black,
    this.alignment = Alignment.center,
    super.key,
  });

  final double maxWidth;
  final double maxHeight;
  final PlPlayerController plPlayerController;
  final VideoDetailController? videoDetailController;
  final CommonIntroController? introController;
  final Widget headerControl;
  final Widget? bottomControl;
  final VoidCallback? onRetry;
  final Widget? danmuWidget;
  final ShowPlayerEpisodes? showEpisodes;
  final VoidCallback? showViewPoints;
  final Color fill;
  final Alignment alignment;

  @override
  State<PLVideoPlayer> createState() => _PLVideoPlayerState();
}

class _PLVideoPlayerState extends State<PLVideoPlayer>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late VideoController videoController;
  late final CommonIntroController introController = widget.introController!;
  late final VideoDetailController videoDetailController =
      widget.videoDetailController!;

  final _playerKey = GlobalKey();
  late final PlayerDanmakuActions _danmakuActions;
  late final PlayerGestures _gestures;
  late final PlayerVideoOutput _videoOutput;

  final _subtitleControlsVisible = ValueNotifier(false);
  StreamSubscription? _controlsListener;
  StreamSubscription? _loadingListener;
  void _onControlChanged(bool val) {
    final visible =
        (val ||
            plPlayerController.dataStatus.loading ||
            _waitingForVideoFrame ||
            plPlayerController.dataStatus.error) &&
        !plPlayerController.controlsLock.value;

    if ((widget.headerControl.key as GlobalKey<TimeBatteryMixin>).currentState
        case final state?) {
      if (state.mounted) {
        state.getBatteryLevelIfNeeded();
        state.provider
          ?..startIfNeeded()
          ..muted = !visible;
        if (visible) {
          state.startClock();
        } else {
          state.stopClock();
        }
      }
    }

    if (visible) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    _subtitleControlsVisible.value = visible;
  }

  void _onFramePresentationChanged() =>
      _onControlChanged(plPlayerController.showControls.value);

  @override
  void initState() {
    super.initState();
    _danmakuActions = PlayerDanmakuActions(
      plPlayerController: plPlayerController,
      durationMs: () => widget.videoDetailController?.data.timeLength,
      liveRoomId: () => (widget.bottomControl as live_bottom.BottomControl)
          .liveRoomCtr
          .roomId,
    );

    _controlsListener = plPlayerController.showControls.listen(
      _onControlChanged,
    );

    _gestures = PlayerGestures(
      plPlayerController: plPlayerController,
      danmakuActions: _danmakuActions,
      context: () => context,
    );
    _videoOutput = PlayerVideoOutput(
      plPlayerController: plPlayerController,
      transformationController: _gestures.transformationController,
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value:
          plPlayerController.showControls.value ||
              plPlayerController.dataStatus.loading ||
              _waitingForVideoFrame ||
              plPlayerController.dataStatus.error
          ? 1
          : 0,
    );
    _subtitleControlsVisible.value =
        _animationController.value != 0 &&
        !plPlayerController.controlsLock.value;
    _loadingListener = plPlayerController.dataStatus.listen(
      (_) => _onControlChanged(plPlayerController.showControls.value),
    );
    plPlayerController.videoFramePresented.addListener(
      _onFramePresentationChanged,
    );
    videoController = _videoOutput.videoController;
  }

  @override
  void dispose() {
    unawaited(_webpCapture.cancel());
    _controlsListener?.cancel();
    _loadingListener?.cancel();
    _subtitleControlsVisible.dispose();
    plPlayerController.videoFramePresented.removeListener(
      _onFramePresentationChanged,
    );
    _animationController.dispose();
    _videoOutput.dispose();
    _gestures.dispose();
    _danmakuActions.dispose();

    super.dispose();
  }

  PlPlayerController get plPlayerController => widget.plPlayerController;

  bool get isFullScreen => plPlayerController.isFullScreen.value;

  double maxWidth = 0;
  double maxHeight = 0;

  @override
  void didUpdateWidget(covariant PLVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plPlayerController, widget.plPlayerController) ||
        !identical(
          oldWidget.videoDetailController,
          widget.videoDetailController,
        )) {
      unawaited(_webpCapture.cancel());
    }
    if (Platform.isAndroid && AndroidHelper.isPipMode) {
      plPlayerController.controls = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    maxWidth = widget.maxWidth;
    maxHeight = widget.maxHeight;
    _videoOutput.updateLayout(
      width: maxWidth,
      height: maxHeight,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      orientation: MediaQuery.orientationOf(context),
    );
    final isFullScreen = this.isFullScreen;
    final isLive = plPlayerController.isLive;

    final child = Stack(
      fit: StackFit.passthrough,
      key: _playerKey,
      children: <Widget>[
        _videoWidget,

        if (widget.danmuWidget case final danmaku?)
          Positioned.fill(top: 4, child: danmaku),

        if (!isLive)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !plPlayerController.enableDragSubtitle,
              child: ValueListenableBuilder(
                valueListenable: _subtitleControlsVisible,
                builder: (context, controlsVisible, _) => Obx(
                  () => PlayerSubtitleView(
                    controller: videoController,
                    configuration: plPlayerController.subtitleConfig.value,
                    controlsVisible: controlsVisible,
                    enableDragSubtitle: plPlayerController.enableDragSubtitle,
                    onUpdatePadding: plPlayerController.onUpdatePadding,
                  ),
                ),
              ),
            ),
          ),

        if (plPlayerController.enableTapDm)
          _danmakuActions.buildOverlay(context, maxWidth),

        // 加载或替换输出时遮住中间画面；底层纹理继续参与 raster。
        ListenableBuilder(
          listenable: _videoOutput,
          builder: (context, _) => Obx(
            () =>
                plPlayerController.dataStatus.loading ||
                    _waitingForVideoFrame ||
                    _videoOutput.protected
                ? Positioned.fill(
                    child: IgnorePointer(child: ColoredBox(color: widget.fill)),
                  )
                : const SizedBox.shrink(),
          ),
        ),

        if (!isLive)
          PlayerSpeedIndicator(
            plPlayerController: plPlayerController,
            isFullScreen: isFullScreen,
          ),

        if (!isLive)
          PlayerSeekIndicator(
            plPlayerController: plPlayerController,
            isFullScreen: isFullScreen,
          ),

        PlayerVolumeIndicator(plPlayerController: plPlayerController),

        _gestures.buildBrightnessIndicator(),

        // 头部、底部控制条
        Positioned.fill(
          top: -1,
          bottom: -1,
          child: ClipRect(
            child: RepaintBoundary(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppBarAni(
                    isTop: true,
                    controller: _animationController,
                    isFullScreen: isFullScreen,
                    removeSafeArea: plPlayerController.removeSafeArea,
                    child: plPlayerController.isDesktopPip
                        ? GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (_) => windowManager.startDragging(),
                            child: widget.headerControl,
                          )
                        : widget.headerControl,
                  ),
                  AppBarAni(
                    isTop: false,
                    controller: _animationController,
                    isFullScreen: isFullScreen,
                    removeSafeArea: plPlayerController.removeSafeArea,
                    child:
                        widget.bottomControl ??
                        BottomControl(
                          maxWidth: maxWidth,
                          isFullScreen: isFullScreen,
                          controller: plPlayerController,
                          videoDetailController: videoDetailController,
                          buildBottomControl: () => VideoControls(
                            plPlayerController: plPlayerController,
                            videoDetailController: videoDetailController,
                            introController: introController,
                            maxWidth: maxWidth,
                            isLandscape: maxWidth > maxHeight,
                            isFullScreen: isFullScreen,
                            showEpisodes: widget.showEpisodes,
                            showViewPoints: widget.showViewPoints,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),

        _gestures.buildRestoreButton(),

        if (!isLive)
          CompactVideoProgress(
            plPlayerController: plPlayerController,
            videoDetailController: videoDetailController,
            isFullScreen: isFullScreen,
          ),

        if (!isLive && plPlayerController.showSeekPreview)
          buildSeekPreviewWidget(
            plPlayerController,
            maxWidth,
            maxHeight,
          ),

        if (isFullScreen || plPlayerController.isDesktopPip) ...[
          // 锁
          if (plPlayerController.showFsLockBtn)
            ViewSafeArea(
              right: false,
              left: !plPlayerController.removeSafeArea,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionalTranslation(
                  translation: const Offset(1, -0.4),
                  child: Obx(
                    () => Offstage(
                      offstage: !plPlayerController.showControls.value,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Obx(() {
                          final controlsLock =
                              plPlayerController.controlsLock.value;
                          return ComBtn(
                            tooltip: controlsLock ? '解锁' : '锁定',
                            icon: controlsLock
                                ? Icon(
                                    FontAwesomeIcons.lock.data,
                                    size: 15,
                                    color: Colors.white,
                                  )
                                : Icon(
                                    FontAwesomeIcons.lockOpen.data,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                            onTap: () =>
                                plPlayerController.onLockControl(!controlsLock),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 截图
          if (plPlayerController.showFsScreenshotBtn)
            ViewSafeArea(
              left: false,
              right: !plPlayerController.removeSafeArea,
              child: Obx(
                () => Align(
                  alignment: Alignment.centerRight,
                  child: FractionalTranslation(
                    translation: const Offset(-1, -0.4),
                    child: Offstage(
                      offstage: !plPlayerController.showControls.value,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: ComBtn(
                          tooltip: '截图',
                          icon: const Icon(
                            Icons.photo_camera,
                            size: 20,
                            color: Colors.white,
                          ),
                          onLongPress:
                              (Platform.isAndroid || kDebugMode) && !isLive
                              ? _screenshotWebp
                              : null,
                          onTap: plPlayerController.takeScreenshot,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],

        ListenableBuilder(
          listenable: _videoOutput,
          builder: (context, _) => Obx(() {
            final recovery = plPlayerController.audioRecoveryStatus.value;
            final recoveringAudio =
                recovery != AudioRecoveryStatus.idle &&
                plPlayerController.wantsToPlay &&
                !plPlayerController.isMuted;
            if (plPlayerController.dataStatus.loading ||
                recoveringAudio ||
                plPlayerController.isVideoStalled.value ||
                _waitingForVideoFrame ||
                plPlayerController.dataStatus.error ||
                _videoOutput.protected ||
                (plPlayerController.isBuffering.value &&
                    plPlayerController.playerStatus.isPlaying)) {
              return PlayerLoadingIndicator(
                failed:
                    plPlayerController.dataStatus.error ||
                    recovery == AudioRecoveryStatus.failed,
                message: recoveringAudio
                    ? recovery == AudioRecoveryStatus.failed
                          ? '声音恢复失败，点击重试'
                          : '正在恢复声音...'
                    : plPlayerController.isVideoStalled.value
                    ? '正在恢复画面...'
                    : null,
                buffered:
                    (plPlayerController.buffered.value -
                            plPlayerController.position.value)
                        .clamp(0, 1 << 30),
                onRetry: widget.onRetry ?? plPlayerController.refreshPlayer,
              );
            } else {
              return const SizedBox.shrink();
            }
          }),
        ),

        /// 点击 快进/快退
        if (!isLive)
          Obx(() {
            final mountSeekBackwardButton =
                plPlayerController.mountSeekBackwardButton.value;
            final mountSeekForwardButton =
                plPlayerController.mountSeekForwardButton.value;
            return mountSeekBackwardButton || mountSeekForwardButton
                ? Positioned.fill(
                    child: Row(
                      children: [
                        if (mountSeekBackwardButton)
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 500),
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: child,
                              ),
                              child: SeekIndicator(
                                forward: false,
                                duration:
                                    plPlayerController.fastForBackwardDuration,
                                onSubmitted: (Duration value) {
                                  plPlayerController
                                    ..mountSeekBackwardButton.value = false
                                    ..onBackward(value);
                                },
                              ),
                            ),
                          ),
                        const Spacer(flex: 2),
                        if (mountSeekForwardButton)
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 500),
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: child,
                              ),
                              child: SeekIndicator(
                                forward: true,
                                duration:
                                    plPlayerController.fastForBackwardDuration,
                                onSubmitted: (Duration value) {
                                  plPlayerController
                                    ..mountSeekForwardButton.value = false
                                    ..onForward(value);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink();
          }),
      ],
    );
    if (PlatformUtils.isDesktop) {
      return Obx(
        () => MouseRegion(
          cursor: !plPlayerController.showControls.value && isFullScreen
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          onEnter: (_) => plPlayerController.controls = true,
          onHover: (_) => plPlayerController.controls = true,
          onExit: (_) => plPlayerController.controls =
              widget.videoDetailController?.showSteinEdgeInfo.value ?? false,
          child: child,
        ),
      );
    }
    return child;
  }

  bool get _waitingForVideoFrame => _videoOutput.waitingForVideoFrame;

  Widget get _videoWidget {
    return Container(
      clipBehavior: .none,
      width: maxWidth,
      height: maxHeight,
      color: widget.fill,
      child: ListenableBuilder(
        listenable: plPlayerController.videoFramePresented,
        builder: (context, _) => Obx(
          () {
            final loaded = plPlayerController.dataStatus.loaded;
            if (loaded && plPlayerController.isDesktopPip) {
              _videoOutput.notifyDesktopFramePresented();
            }
            return _gestures.buildSurface(
              width: maxWidth,
              height: maxHeight,
              child: Obx(
                () {
                  final videoFit = plPlayerController.videoFit.value;
                  return Transform.flip(
                    flipX: plPlayerController.flipX.value,
                    flipY: plPlayerController.flipY.value,
                    child: FittedBox(
                      fit: videoFit.boxFit,
                      alignment: widget.alignment,
                      child: _videoOutput.buildFrame(
                        fill: widget.fill,
                        fit: videoFit,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  final _webpCapture = PlayerWebpCapture();

  Future<void> _screenshotWebp() {
    final controller = plPlayerController;
    final details = widget.videoDetailController;
    return _webpCapture.capture(
      context: context,
      controller: controller,
      details: details,
      isCurrent: () =>
          mounted &&
          identical(widget.plPlayerController, controller) &&
          identical(widget.videoDetailController, details),
    );
  }
}
