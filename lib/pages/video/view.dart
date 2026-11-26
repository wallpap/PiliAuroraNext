import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:pili_aurora_next/common/assets.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/flutter/pop_scope.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/keep_alive_wrapper.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView, platformAlwaysClampingPhysics, platformClampingPhysics;
import 'package:pili_aurora_next/common/widgets/simple_app_bar.dart';
import 'package:pili_aurora_next/common/widgets/sliver/video_header.dart';
import 'package:pili_aurora_next/common/widgets/svg/play_icon.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_video_tools.dart';
import 'package:pili_aurora_next/features/playback/domain/episode_panel_type.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/result.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/episode.dart'
    as ugc;
import 'package:pili_aurora_next/features/playback/domain/video_detail/page.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/ugc_season.dart';
import 'package:pili_aurora_next/features/playback/domain/video_tag/data.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/danmaku/view.dart';
import 'package:pili_aurora_next/pages/episode_panel/view.dart';
import 'package:pili_aurora_next/pages/video/ai_conclusion/view.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/local/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/local/view.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/view.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/widgets/intro_detail.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/view.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/page.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/season.dart';
import 'package:pili_aurora_next/pages/video/member/view.dart';
import 'package:pili_aurora_next/pages/video/related/view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/content_discovery/application/related_videos.dart';
import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';
import 'package:pili_aurora_next/features/member_space/application/video_author.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';
import 'package:pili_aurora_next/pages/video/reply/view.dart';
import 'package:pili_aurora_next/pages/video/view_point/view.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_control.dart';
import 'package:pili_aurora_next/pages/video/widgets/more_settings_sheet.dart';
import 'package:pili_aurora_next/pages/video/widgets/detail_panels.dart';
import 'package:pili_aurora_next/pages/video/widgets/intro_layout.dart';
import 'package:pili_aurora_next/pages/video/widgets/player_focus.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/fullscreen.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/player_loading.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/desktop_window_controls.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/desktop_playback_request.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/platform/android/bindings.g.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/platform/android/max_screen_size.dart';
import 'package:pili_aurora_next/platform/mobile_observer.dart';
import 'package:pili_aurora_next/core/text/number_format.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

class VideoDetailPageV extends ConsumerStatefulWidget {
  const VideoDetailPageV({super.key});

  @override
  ConsumerState<VideoDetailPageV> createState() => _VideoDetailPageVState();
}

class _VideoDetailPageVState extends ConsumerState<VideoDetailPageV>
    with
        RouteAware,
        RouteAwareMixin,
        WidgetsBindingObserver,
        TickerProviderStateMixin {
  final heroTag = Get.arguments['heroTag'];

  late final VideoDetailController videoDetailController;
  final _replyOwner = Object();
  final _replyScroll = ScrollController();
  final _replyTarget = ValueNotifier<({int aid, CommentTarget target})?>(null);
  final _replyCount = ValueNotifier<int?>(null);
  final _loadedReplyCount = ValueNotifier<int?>(null);

  void _onReplyAccountChanged() {
    _replyCount.value = null;
    _loadedReplyCount.value = null;
  }

  void _onReplyTargetChanged() {
    final controller = videoDetailController;
    final oid = controller.videoType == VideoType.pugv
        ? controller.epId
        : controller.aid;
    _replyTarget.value = oid == null || oid <= 0
        ? null
        : (
            aid: controller.aid,
            target: (oid: oid, type: controller.videoType.replyType),
          );
    _onReplyAccountChanged();
    if (_replyScroll.hasClients) _replyScroll.jumpTo(0);
  }

  PlPlayerController? plPlayerController;

  // intro ctr
  late final CommonIntroController introController =
      videoDetailController.isFileSource
      ? localIntroController
      : videoDetailController.isUgc
      ? ugcIntroController
      : pgcIntroController;
  late final UgcIntroController ugcIntroController;
  late final PgcIntroController pgcIntroController;
  late final LocalIntroController localIntroController;

  bool get autoExitFullscreen =>
      videoDetailController.plPlayerController.autoExitFullscreen;

  bool get autoPlayEnable =>
      videoDetailController.plPlayerController.autoPlayEnable;

  bool get enableVerticalExpand =>
      videoDetailController.plPlayerController.enableVerticalExpand;

  bool get pipNoDanmaku =>
      videoDetailController.plPlayerController.pipNoDanmaku;

  bool isShowing = true;

  bool get isFullScreen =>
      videoDetailController.plPlayerController.isFullScreen.value;

  bool get _shouldShowSeasonPanel {
    if (videoDetailController.isFileSource ||
        isPortrait ||
        !videoDetailController.isUgc) {
      return false;
    }
    late final videoDetail = ugcIntroController.videoDetail.value;
    return videoDetailController.plPlayerController.horizontalSeasonPanel &&
        (videoDetail.ugcSeason != null ||
            ((videoDetail.pages?.length ?? 0) > 1));
  }

  final videoReplyPanelKey = GlobalKey();
  final videoRelatedKey = GlobalKey();
  final videoIntroKey = GlobalKey();
  late final _relatedQuery = ValueNotifier(
    RelatedVideoQuery(videoDetailController.bvid),
  );
  ProviderSubscription<RelatedVideosState>? _relatedSubscription;
  ({Object source, bool Function() isCurrent})? _pendingRelatedPlay;
  AnchoredSpaceArchiveQuery? _authorArchiveQuery;
  ProviderSubscription<VideoAuthorState>? _authorSubscription;
  ProviderSubscription<SpaceArchiveState>? _authorArchiveSubscription;

  void _bindRelatedVideos() {
    _relatedSubscription = ref.listenManual(
      relatedVideosProvider(_relatedQuery.value),
      (_, next) {
        final pending = _pendingRelatedPlay;
        if (pending == null) return;
        if (!identical(pending.source, next.source) ||
            !pending.isCurrent() ||
            !isShowing ||
            plPlayerController?.playRepeat != PlayRepeat.autoPlayRelated) {
          _pendingRelatedPlay = null;
          return;
        }
        if (next.loadingMore) return;
        _pendingRelatedPlay = null;
        _playFromRelated(next);
      },
    );
  }

  void _relatedTargetChanged(String bvid) {
    _pendingRelatedPlay = null;
    if (_relatedQuery.value.bvid == bvid) return;
    _relatedSubscription?.close();
    _relatedQuery.value = RelatedVideoQuery(bvid);
    _bindRelatedVideos();
  }

  bool _playRelated(bool Function() isCurrent) {
    if (!isCurrent()) return false;
    final snapshot = _relatedSubscription!.read();
    if (snapshot.loading.isSuccess && !snapshot.loadingMore) {
      return _playFromRelated(snapshot);
    }
    if (snapshot.loadingMore || snapshot.error == null) {
      _pendingRelatedPlay = (source: snapshot.source, isCurrent: isCurrent);
    }
    return false;
  }

  bool _playFromRelated(RelatedVideosState snapshot) {
    final items = snapshot.loading.dataOrNull;
    if (items == null) return false;
    final target = items.firstOrNull;
    if (target == null) {
      SmartDialog.showToast('暂无相关视频，停止连播');
      return false;
    }
    unawaited(
      ugcIntroController.onChangeEpisode(
        ugc.BaseEpisodeItem(
          aid: target.aid,
          bvid: target.bvid,
          cid: target.cid,
          cover: target.cover,
        ),
      ),
    );
    return true;
  }

  late final _desktopRequest = _createDesktopRequest;
  DesktopPlaybackRequest _createDesktopRequest() =>
      DesktopPlaybackRequest.video({
        'aid': videoDetailController.aid,
        'bvid': videoDetailController.bvid,
        'cid': videoDetailController.cid.value,
        'epId': videoDetailController.epId,
        'seasonId': videoDetailController.seasonId,
        'pgcType': videoDetailController.pgcType,
        'videoType': videoDetailController.videoType,
        'pgcApi': videoDetailController.args['pgcApi'],
        'isVertical': videoDetailController.isVertical.value,
        'cover': videoDetailController.cover.value,
        'title': videoDetailController.args['title'] ?? '',
        'progress':
            videoDetailController.plPlayerController.positionInMilliseconds,
        'heroTag': 'desktop-${videoDetailController.cid.value}',
        if (videoDetailController.isFileSource) ...{
          'sourceType': SourceType.file,
          'entry': videoDetailController.entry,
          'dirPath': videoDetailController.args['dirPath'],
        },
      });

  @override
  void initState() {
    super.initState();
    videoDetailController = VideoDetailController()..open(Get.arguments, this);
    PlPlayerController.setPlayCallBack(playCallBack, owner: this);
    videoDetailController.plPlayerController.desktopPlaybackRequest =
        _desktopRequest;

    if (videoDetailController.removeSafeArea) {
      hideSystemBar();
    }

    if (videoDetailController.showReply) {
      AccountScope.changes.addListener(_onReplyAccountChanged);
      _onReplyTargetChanged();
      videoDetailController.onReplyTargetChanged = _onReplyTargetChanged;
      videoDetailController.onReplyCount = (count) => _replyCount.value = count;
    }

    if (videoDetailController.isFileSource) {
      localIntroController = LocalIntroController();
    } else if (videoDetailController.isUgc) {
      ugcIntroController = UgcIntroController();
    } else {
      pgcIntroController = PgcIntroController();
    }
    videoDetailController.introduction = introController;
    introController.open(videoDetailController, this);
    if (introController case final UgcIntroController ugc) {
      if (videoDetailController.showRelatedVideo) {
        _bindRelatedVideos();
        ugc
          ..onRelatedTargetChanged = _relatedTargetChanged
          ..onPlayRelated = _playRelated;
      }
    }

    videoSourceInit();

    addObserverMobile(this);
  }

  // 获取视频资源，初始化播放器
  void videoSourceInit() {
    videoDetailController.queryVideoUrl(autoFullScreenFlag: true);
    if (videoDetailController.autoPlay) {
      plPlayerController = videoDetailController.plPlayerController;
      plPlayerController!
        ..addStatusLister(playerListener)
        ..addCoarsePositionListener(positionListener);
    }
  }

  void positionListener(Duration position) {
    videoDetailController.observePlaybackProgress(position);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isResume = state == .resumed;
    final ctr = videoDetailController.plPlayerController..visible = isResume;
    if (isResume) {
      if (!ctr.showDanmaku) {
        introController.startTimer();
        ctr.showDanmaku = true;
      }
    } else if (state == .paused) {
      introController.cancelTimer();
      ctr.showDanmaku = false;
    }
  }

  Future<void>? playCallBack() {
    if (!isShowing) {
      plPlayerController
        ?..addStatusLister(playerListener)
        ..addCoarsePositionListener(positionListener);
    }
    return plPlayerController?.play();
  }

  // 播放器状态监听
  Future<void> playerListener(PlayerStatus status) async {
    if (!videoDetailController.playbackOwner.isActive) return;
    videoDetailController.observePlaybackProgress();
    final isPlaying = status.isPlaying;
    try {
      if (videoDetailController.scrollCtr.hasClients) {
        if (isPlaying) {
          if (!videoDetailController.isExpanding &&
              videoDetailController.scrollCtr.offset != 0 &&
              !videoDetailController.animationController.isAnimating) {
            videoDetailController.isExpanding = true;
            videoDetailController.animationController.forward(
              from:
                  1 -
                  videoDetailController.scrollCtr.offset /
                      videoDetailController.videoHeight,
            );
          } else {
            videoDetailController.refreshPage();
          }
        } else {
          videoDetailController.refreshPage();
        }
      }
    } catch (e, stackTrace) {
      logger.w('handle player status: $e', error: e, stackTrace: stackTrace);
    }

    if (status.isCompleted) {
      try {
        if (videoDetailController
                .steinEdgeInfo
                ?.edges
                ?.questions
                ?.firstOrNull
                ?.choices
                ?.isNotEmpty ==
            true) {
          videoDetailController.showSteinEdgeInfo.value = true;
          return;
        }
      } catch (_) {}

      bool exitFlag = true;

      /// 顺序播放 列表循环
      if (!videoDetailController.completeShutdownTimer()) {
        switch (plPlayerController!.playRepeat) {
          case PlayRepeat.singleCycle:
            exitFlag = false;
            plPlayerController!.play(repeat: true);
          case PlayRepeat.listOrder:
          case PlayRepeat.listCycle:
          case PlayRepeat.autoPlayRelated:
            exitFlag = !introController.nextPlay();
          case PlayRepeat.pause:
        }
      }

      if (exitFlag) {
        if (autoExitFullscreen) {
          plPlayerController!.triggerFullScreen(status: false);
          if (plPlayerController!.controlsLock.value) {
            plPlayerController!.onLockControl(false);
          }
        } else {
          if (plPlayerController!.controlsLock.value &&
              (!Platform.isAndroid || !AndroidHelper.isPipMode)) {
            plPlayerController!.onLockControl(false);
          }
        }
      }
    }
  }

  /// 未开启自动播放时触发播放
  Future<void>? handlePlay() {
    final plPlayerController = this.plPlayerController =
        videoDetailController.plPlayerController;
    videoDetailController.autoPlay = true;
    plPlayerController
      ..addStatusLister(playerListener)
      ..addCoarsePositionListener(positionListener);
    if (!videoDetailController.isFileSource) {
      if (videoDetailController.isQuerying) {
        return plPlayerController.play();
      }
      if (videoDetailController.videoUrl == null) {
        return videoDetailController.queryVideoUrl(
          startPolicy: PlaybackStartPolicy.play,
          autoFullScreenFlag: true,
        );
      }
    }
    if (videoDetailController.videoState.value &&
        plPlayerController.currentPlaybackSnapshot.phase ==
            PlaybackPhase.ready) {
      if (plPlayerController.autoEnterFullScreen) {
        plPlayerController.triggerFullScreen();
      }
      return plPlayerController.play();
    } else {
      return videoDetailController.playerInit(
        autoplay: true,
        autoFullScreenFlag: true,
      );
    }
  }

  @override
  void dispose() {
    if (_relatedSubscription != null) {
      ugcIntroController
        ..onRelatedTargetChanged = null
        ..onPlayRelated = null;
      _pendingRelatedPlay = null;
      _relatedSubscription!.close();
      _relatedQuery.dispose();
    }
    AccountScope.changes.removeListener(_onReplyAccountChanged);
    videoDetailController.onReplyTargetChanged = null;
    videoDetailController.onReplyCount = null;
    _replyTarget.dispose();
    _replyCount.dispose();
    _loadedReplyCount.dispose();
    _replyScroll.dispose();
    PlPlayerController.setPlayCallBack(null, owner: this);
    plPlayerController
      ?..removeStatusLister(playerListener)
      ..removeCoarsePositionListener(positionListener);

    _authorSubscription?.close();
    _authorArchiveSubscription?.close();

    if (!videoDetailController.removeSafeArea) {
      showSystemBar();
    }

    if (!videoDetailController.plPlayerController.isCloseAll) {
      videoPlayerServiceHandler?.onVideoDetailDispose(heroTag);
      videoDetailController.makeHeartBeat();
    }
    removeObserverMobile(this);
    final player = videoDetailController.plPlayerController;
    if (identical(player.desktopPlaybackRequest, _desktopRequest)) {
      player.desktopPlaybackRequest = null;
    }
    introController.close();
    videoDetailController.close();

    super.dispose();
  }

  @override
  // 离开当前页面时
  void didPushNext() {
    super.didPushNext();
    isShowing = false;
    _pendingRelatedPlay = null;

    removeObserverMobile(this);

    if (Platform.isAndroid && !videoDetailController.setSystemBrightness) {
      ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
    }

    introController.cancelTimer();

    videoDetailController
      ..holdPlaybackForRoute()
      ..videoState.value = false
      ..cancelBlockListener()
      ..brightness = plPlayerController?.brightness.value;
    if (plPlayerController != null) {
      videoDetailController.makeHeartBeat();
      plPlayerController!
        ..removeStatusLister(playerListener)
        ..removeCoarsePositionListener(positionListener);
    }
  }

  @override
  // 返回当前页面时
  Future<void> didPopNext() async {
    final restore = videoDetailController.restorePlaybackAfterRoute();
    videoDetailController.plPlayerController.desktopPlaybackRequest =
        _desktopRequest;
    super.didPopNext();

    if (videoDetailController.plPlayerController.isCloseAll) {
      await restore;
      return;
    }

    isShowing = true;

    addObserverMobile(this);

    plPlayerController?.isLive = false;
    PlPlayerController.setPlayCallBack(
      playCallBack,
      owner: this,
    );

    introController.startTimer();

    if (mounted &&
        Platform.isAndroid &&
        !videoDetailController.setSystemBrightness) {
      if (videoDetailController.brightness != null) {
        plPlayerController?.brightness.value =
            videoDetailController.brightness!;
        if (videoDetailController.brightness != -1.0) {
          ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
            videoDetailController.brightness!,
          );
        } else {
          ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
        }
      } else {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      }
    }

    plPlayerController
      ?..addStatusLister(playerListener)
      ..addCoarsePositionListener(positionListener);
    if (plPlayerController?.playerStatus.isPlaying == true) {
      playerListener(PlayerStatus.playing);
    }
    await restore;
    if (!mounted) return;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (videoDetailController.removeSafeArea) {
      padding = .zero;
    } else {
      padding = MediaQuery.viewPaddingOf(context);
    }

    final size = MediaQuery.sizeOf(context);
    maxWidth = size.width;
    maxHeight = size.height;
    isWindowMode = MaxScreenSize.isWindowMode(
      width: maxWidth * videoDetailController.uiScale,
      height: maxHeight * videoDetailController.uiScale,
    );
    videoDetailController.plPlayerController.screenRatio = maxHeight / maxWidth;

    final shortestSide = size.shortestSide;
    final minVideoHeight = shortestSide / Style.aspectRatio16x9;
    final maxVideoHeight = max(size.longestSide * 0.65, shortestSide);
    videoDetailController
      ..isPortrait = isPortrait = maxHeight >= maxWidth
      ..minVideoHeight = minVideoHeight
      ..maxVideoHeight = maxVideoHeight
      ..videoHeight = videoDetailController.isVertical.value
          ? maxVideoHeight
          : minVideoHeight;

    theme = videoDetailController.plPlayerController.darkVideoPage
        ? ThemeUtils.darkTheme
        : Theme.of(context);
  }

  bool removeAppBar(bool isFullScreen) =>
      PlatformUtils.isDesktop ||
      videoDetailController.removeSafeArea ||
      (isWindowMode && isFullScreen && !isPortrait);

  Widget get childWhenDisabled {
    return Obx(
      () {
        final isFullScreen = this.isFullScreen;
        return SimpleScaffold(
          appBar: removeAppBar(isFullScreen)
              ? null
              : ValueListenableBuilder(
                  valueListenable: videoDetailController.scrollRatio,
                  builder: (context, scrollRatio, child) {
                    final brightness = colorScheme.brightness;
                    final Brightness statusBarBrightness;
                    final Brightness statusBarIconBrightness;
                    final backgroundColor = isPortrait && scrollRatio > 0
                        ? Color.lerp(
                            Colors.black,
                            colorScheme.surface,
                            scrollRatio,
                          )!
                        : Colors.black;
                    if (isPortrait && scrollRatio >= 0.5) {
                      statusBarBrightness = brightness;
                      statusBarIconBrightness = brightness.reverse;
                    } else {
                      statusBarBrightness = .dark;
                      statusBarIconBrightness = .light;
                    }
                    return SimpleAppBar(
                      height: padding.top,
                      backgroundColor: backgroundColor,
                      brightness: brightness,
                      statusBarBrightness: statusBarBrightness,
                      statusBarIconBrightness: statusBarIconBrightness,
                    );
                  },
                ),
          body: ExtendedNestedScrollView(
            onlyOneScrollInBody: true,
            physics: platformClampingPhysics,
            key: videoDetailController.scrollKey,
            controller: videoDetailController.scrollCtr,
            scrollBehavior: const NoOverscrollIndicator(),
            pinnedHeaderSliverHeightBuilder: () {
              double pinnedHeight = this.isFullScreen || !isPortrait
                  ? maxHeight - (isWindowMode && !isPortrait ? 0 : padding.top)
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.isCollapsing ||
                        (plPlayerController?.playerStatus.isPlaying ?? false)
                  ? videoDetailController.minVideoHeight
                  : kToolbarHeight;
              if (videoDetailController.isExpanding &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isExpanding = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.scrollRatio.value = 0;
                  videoDetailController.refreshPage();
                });
              } else if (videoDetailController.isCollapsing &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isCollapsing = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.refreshPage();
                });
              }
              return pinnedHeight;
            },
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final height = isFullScreen || !isPortrait
                  ? maxHeight - (isWindowMode && !isPortrait ? 0 : padding.top)
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.videoHeight;
              return [
                VideoHeader(
                  minExtent: kToolbarHeight,
                  maxExtent: height,
                  minVideoHeight: videoDetailController.minVideoHeight,
                  onScrollRatioChanged: videoDetailController.updateScrollRatio,
                  child: Stack(
                    clipBehavior: .none,
                    children: [
                      SizedBox(
                        width: maxWidth,
                        height: height,
                        child: videoPlayer(width: maxWidth, height: height),
                      ),
                      _buildHeaderOverlay(),
                    ],
                  ),
                ),
              ];
            },
            body: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                children: [
                  buildTabBar(onTap: videoDetailController.animToTop),
                  Expanded(
                    child: tabBarView(
                      hitTestBehavior: .translucent,
                      controller: videoDetailController.tabCtr,
                      children: [
                        videoIntro(isHorizontal: false, needCtr: false),
                        if (videoDetailController.showReply)
                          videoReplyPanel(isNested: true),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayToolBar(double scrollRatio) {
    final IconData icon;
    final String playStat;
    if (videoDetailController.playedTime == null) {
      icon = Icons.play_arrow_rounded;
      playStat = '立即';
    } else if (plPlayerController!.isCompleted) {
      icon = CustomIcons.replay_rounded;
      playStat = '重新';
    } else {
      icon = Icons.play_arrow_rounded;
      playStat = '继续';
    }
    final playBtn = Row(
      spacing: 2,
      mainAxisSize: .min,
      children: [
        Icon(icon, color: colorScheme.primary),
        Text(
          '$playStat播放',
          style: TextStyle(color: colorScheme.primary),
        ),
      ],
    );
    return Opacity(
      opacity: scrollRatio,
      child: Container(
        color: colorScheme.surface,
        alignment: .topCenter,
        child: SizedBox(
          height: kToolbarHeight,
          child: Stack(
            clipBehavior: .none,
            children: [
              Align(
                alignment: .centerLeft,
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回',
                        icon: Icon(
                          FontAwesomeIcons.arrowLeft.data,
                          size: 15,
                          color: colorScheme.onSurface,
                        ),
                        onPressed: Get.back,
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回主页',
                        icon: Icon(
                          FontAwesomeIcons.house.data,
                          size: 15,
                          color: colorScheme.onSurface,
                        ),
                        onPressed:
                            videoDetailController.plPlayerController.onCloseAll,
                      ),
                    ),
                  ],
                ),
              ),
              Center(child: playBtn),
              Align(
                alignment: .centerRight,
                child: _moreBtn(colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderOverlay() {
    return ValueListenableBuilder(
      valueListenable: videoDetailController.scrollRatio,
      builder: (context, scrollRatio, child) {
        if (scrollRatio == 0) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          bottom: -1,
          child: GestureDetector(
            onTap: () {
              if (!videoDetailController.autoPlay ||
                  plPlayerController == null ||
                  videoDetailController.playedTime == null) {
                handlePlay();
              } else {
                plPlayerController!.onDoubleTapCenter();
              }
            },
            behavior: .opaque,
            child: _buildOverlayToolBar(scrollRatio),
          ),
        );
      },
    );
  }

  Widget get childWhenDisabledLandscape => Obx(
    () {
      final isFullScreen = this.isFullScreen;
      return SimpleScaffold(
        appBar: removeAppBar(isFullScreen)
            ? null
            : SimpleAppBar(
                height: padding.top,
                brightness: colorScheme.brightness,
              ),
        body: Padding(
          padding: isFullScreen
              ? EdgeInsets.zero
              : padding.copyWith(top: 0, bottom: 0),
          child: childWhenDisabledLandscapeInner(isFullScreen),
        ),
      );
    },
  );

  Widget childSplit(double ratio) {
    final double videoHeight = maxHeight - padding.vertical;
    final double width = videoHeight * ratio;
    final videoWidth = isFullScreen ? maxWidth : width;
    final introWidth = maxWidth - width - padding.horizontal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: videoWidth,
          height: videoHeight,
          child: videoPlayer(
            width: videoWidth,
            height: videoHeight,
          ),
        ),
        VideoDetailOffstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: introWidth,
            height: maxHeight - padding.top,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(),
                  Expanded(
                    child: tabBarView(
                      controller: videoDetailController.tabCtr,
                      children: [
                        videoIntro(
                          width: introWidth,
                          height: maxHeight,
                        ),
                        if (videoDetailController.showReply) videoReplyPanel(),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget childWhenDisabledLandscapeInner(bool isFullScreen) {
    if (enableVerticalExpand) {
      return ValueListenableBuilder(
        valueListenable: videoDetailController.isVertical,
        builder: (context, vertical, child) {
          if (vertical && !isPortrait) {
            final double videoHeight = maxHeight - padding.vertical;
            final double width = videoHeight / Style.aspectRatio16x9;
            final videoWidth = isFullScreen ? maxWidth : width;
            final introWidth = (maxWidth - padding.horizontal - width) / 2;
            final introHeight = maxHeight - padding.top;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VideoDetailOffstage(
                  offstage: isFullScreen,
                  child: SizedBox(
                    width: introWidth,
                    height: introHeight,
                    child: videoIntro(
                      width: introWidth,
                      height: introHeight,
                    ),
                  ),
                ),
                SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: videoPlayer(
                    width: videoWidth,
                    height: videoHeight,
                  ),
                ),
                VideoDetailOffstage(
                  offstage: isFullScreen,
                  child: SizedBox(
                    width: introWidth,
                    height: introHeight,
                    child: MiniScaffold(
                      key: videoDetailController.childKey,
                      body: Column(
                        children: [
                          buildTabBar(showIntro: false),
                          Expanded(
                            child: tabBarView(
                              controller: videoDetailController.tabCtr,
                              children: [
                                if (videoDetailController.showReply)
                                  videoReplyPanel(),
                                if (_shouldShowSeasonPanel) seasonPanel,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return _childWhenDisabledLandscapeInner(isFullScreen);
        },
      );
    }
    return _childWhenDisabledLandscapeInner(isFullScreen);
  }

  Widget _childWhenDisabledLandscapeInner(bool isFullScreen) {
    double width =
        clampDouble(maxHeight / maxWidth * 1.08, 0.5, 0.7) * maxWidth;
    if (maxWidth >= 560) {
      width = maxWidth - clampDouble(maxWidth - width, 280, 425);
    }
    final videoWidth = isFullScreen ? maxWidth : width;
    final double height = width / Style.aspectRatio16x9;
    final videoHeight = isFullScreen
        ? maxHeight - (isWindowMode && !isPortrait ? 0 : padding.top)
        : height;
    if (height > maxHeight) {
      return childSplit(Style.aspectRatio16x9);
    }
    final introHeight = maxHeight - height - padding.top;
    final showIntro = videoDetailController.isUgc
        ? videoDetailController.showRelatedVideo
        : !videoDetailController.isFileSource;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: videoPlayer(
                width: videoWidth,
                height: videoHeight,
              ),
            ),
            if (!videoDetailController.isFileSource)
              VideoDetailOffstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: width,
                  height: introHeight,
                  child: videoIntro(
                    width: width,
                    height: introHeight,
                    needRelated: false,
                    needCtr: false,
                    pgcHeaderOnly: !videoDetailController.isUgc,
                  ),
                ),
              ),
          ],
        ),
        VideoDetailOffstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: maxWidth - width - padding.horizontal,
            height: maxHeight - padding.top,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(
                    introText: videoDetailController.isUgc ? '相关视频' : '简介',
                    showIntro: videoDetailController.isFileSource || showIntro,
                  ),
                  Expanded(
                    child: tabBarView(
                      controller: videoDetailController.tabCtr,
                      children: [
                        if (videoDetailController.isFileSource)
                          localIntroPanel()
                        else if (showIntro && videoDetailController.isUgc)
                          KeepAliveWrapper(
                            child: CustomScrollView(
                              key: const PageStorageKey(CommonIntroController),
                              controller:
                                  videoDetailController.effectiveIntroScrollCtr,
                              slivers: [
                                RelatedVideoPanel(
                                  key: videoRelatedKey,
                                  query: _relatedQuery,
                                ),
                              ],
                            ),
                          )
                        else if (showIntro)
                          videoIntro(
                            width: maxWidth - width - padding.horizontal,
                            height: maxHeight - padding.top,
                            needRelated: false,
                            needCtr: true,
                            pgcShowHeader: false,
                            pageStorageKey: PageStorageKey(
                              '$heroTag-pgc-content',
                            ),
                          ),
                        if (videoDetailController.showReply) videoReplyPanel(),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget get childWhenDisabledAlmostSquare => Obx(() {
    final isFullScreen = this.isFullScreen;
    return SimpleScaffold(
      appBar: removeAppBar(isFullScreen)
          ? null
          : SimpleAppBar(
              height: padding.top,
              brightness: colorScheme.brightness,
            ),
      body: Padding(
        padding: isFullScreen
            ? EdgeInsets.zero
            : padding.copyWith(top: 0, bottom: 0),
        child: childWhenDisabledAlmostSquareInner(isFullScreen),
      ),
    );
  });

  Widget childWhenDisabledAlmostSquareInner(bool isFullScreen) {
    if (enableVerticalExpand) {
      return ValueListenableBuilder(
        valueListenable: videoDetailController.isVertical,
        builder: (context, vertical, child) {
          if (vertical && !isPortrait) {
            return childSplit(9 / 16);
          }

          return _childWhenDisabledAlmostSquareInner(isFullScreen);
        },
      );
    }

    return _childWhenDisabledAlmostSquareInner(isFullScreen);
  }

  Widget _childWhenDisabledAlmostSquareInner(bool isFullScreen) {
    final shouldShowSeasonPanel = _shouldShowSeasonPanel;
    final double height = maxHeight / 2.5;
    final videoHeight = isFullScreen
        ? maxHeight - (isWindowMode && !isPortrait ? 0 : padding.top)
        : height;
    final bottomHeight = maxHeight - height - padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: maxWidth,
          height: videoHeight,
          child: videoPlayer(
            width: maxWidth,
            height: videoHeight,
          ),
        ),
        VideoDetailOffstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: maxWidth - padding.horizontal,
            height: bottomHeight,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: VideoDetailPanels(
                headerBuilder: (sideBySide) =>
                    buildTabBar(needIndicator: !sideBySide),
                panelBuilders: [
                  (width) => videoIntro(width: width, height: bottomHeight),
                  if (videoDetailController.showReply) (_) => videoReplyPanel(),
                  if (shouldShowSeasonPanel) (_) => seasonPanel,
                ],
                tabbedBuilder: (children) => tabBarView(
                  controller: videoDetailController.tabCtr,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget manualPlayerWidget(double height) => ValueListenableBuilder(
    valueListenable: videoDetailController.autoplayEnabled,
    builder: (context, autoplay, child) {
      if (!autoplay) {
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: kToolbarHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回',
                      icon: Icon(
                        FontAwesomeIcons.arrowLeft.data,
                        size: 15,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed: Get.back,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回主页',
                      icon: Icon(
                        FontAwesomeIcons.house.data,
                        size: 15,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed:
                          videoDetailController.plPlayerController.onCloseAll,
                    ),
                  ),
                  const Spacer(),
                  _moreBtn(
                    Colors.white,
                    shadows: const [
                      Shadow(
                        blurRadius: 1.5,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: height - 70,
              child: const PlayIcon(),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    },
  );

  void _showMoreSettings() {
    final header = videoDetailController.headerCtrKey.currentState;
    if (header is HeaderControlState) {
      header.showSettingSheet();
    } else {
      unawaited(
        showVideoMoreSettings(
          context,
          controller: videoDetailController,
          introController: introController,
        ),
      );
    }
  }

  Widget _moreBtn(Color color, {List<Shadow>? shadows}) => IconButton(
    tooltip: '更多设置',
    onPressed: _showMoreSettings,
    icon: Icon(size: 22, Icons.more_vert, color: color, shadows: shadows),
  );

  Widget plPlayer({
    required double width,
    required double height,
    bool isPipMode = false,
  }) => popScope(
    key: videoDetailController.videoPlayerKey,
    canPop:
        !isFullScreen &&
        !videoDetailController.plPlayerController.isDesktopPip &&
        (videoDetailController.horizontalScreen || isPortrait),
    onPopInvokedWithResult:
        videoDetailController.plPlayerController.onPopInvokedWithResult,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        videoDetailController.autoplayEnabled,
        videoDetailController.videoState,
        videoDetailController.plPlayerController.videoControllerListenable,
      ]),
      builder: (context, child) => !videoDetailController.autoPlay
          ? const SizedBox.shrink()
          : !videoDetailController.videoState.value ||
                plPlayerController?.videoController == null
          ? SizedBox(
              width: width,
              height: height,
              child: Obx(
                () => PlayerLoadingPanel(
                  headerControl:
                      videoDetailController.plPlayerController.isDesktopPip
                      ? GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onPanStart: (_) => windowManager.startDragging(),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              DesktopWindowControls(
                                controller:
                                    videoDetailController.plPlayerController,
                              ),
                            ],
                          ),
                        )
                      : null,
                  failed:
                      videoDetailController.plPlayerController.dataStatus.error,
                  onRetry: videoDetailController.retryPlayback,
                ),
              ),
            )
          : PLVideoPlayer(
              key: ObjectKey(plPlayerController?.videoController),
              maxWidth: width,
              maxHeight: height,
              plPlayerController: plPlayerController!,
              onRetry: videoDetailController.retryPlayback,
              videoDetailController: videoDetailController,
              introController: introController,
              headerControl: HeaderControl(
                key: videoDetailController.headerCtrKey,
                isPortrait: isPortrait,
                controller: videoDetailController.plPlayerController,
                videoDetailCtr: videoDetailController,
                introController: introController,
              ),
              danmuWidget: isPipMode && pipNoDanmaku
                  ? null
                  : ValueListenableBuilder(
                      valueListenable: videoDetailController.cid,
                      builder: (context, cid, child) => Obx(
                        () => PlDanmaku(
                          key: ValueKey(cid),
                          isPipMode: isPipMode,
                          cid: cid,
                          playerController: plPlayerController!,
                          isFullScreen: plPlayerController!.isFullScreen.value,
                          isFileSource: videoDetailController.isFileSource,
                          size: Size(width, height),
                        ),
                      ),
                    ),
              showEpisodes: showEpisodes,
              showViewPoints: showViewPoints,
            ),
    ),
  );

  late ThemeData theme;
  ColorScheme get colorScheme => theme.colorScheme;
  late bool isPortrait;
  late double maxWidth;
  late double maxHeight;
  bool isWindowMode = false;
  late EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (videoDetailController.plPlayerController.isPipMode) {
      child = plPlayer(width: maxWidth, height: maxHeight, isPipMode: true);
    } else if (!videoDetailController.horizontalScreen) {
      child = childWhenDisabled;
    } else if (maxWidth / maxHeight >= kScreenRatio) {
      child = childWhenDisabledLandscape;
    } else if (maxWidth / Style.aspectRatio16x9 < 0.4 * maxHeight) {
      child = childWhenDisabled;
    } else {
      child = childWhenDisabledAlmostSquare;
    }
    if (videoDetailController.plPlayerController.keyboardControl) {
      child = PlayerFocus(
        plPlayerController: videoDetailController.plPlayerController,
        introController: introController,
        onSendDanmaku: videoDetailController.showShootDanmakuSheet,
        canPlay: () {
          if (videoDetailController.autoPlay) {
            return true;
          }
          handlePlay();
          return false;
        },
        onSkipSegment: videoDetailController.onSkipSegment,
        child: child,
      );
    }
    return videoDetailController.plPlayerController.darkVideoPage
        ? Theme(data: theme, child: child)
        : child;
  }

  Widget buildTabBar({
    bool needIndicator = true,
    String? introText,
    bool showIntro = true,
    VoidCallback? onTap,
  }) {
    final tabs = [
      if (showIntro)
        videoDetailController.isFileSource ? '离线视频' : introText ?? '简介',
      if (videoDetailController.showReply) '评论',
      if (_shouldShowSeasonPanel) '播放列表',
    ];
    if (videoDetailController.tabCtr.length != tabs.length) {
      videoDetailController.tabCtr.dispose();
      videoDetailController.tabCtr = TabController(
        vsync: this,
        length: tabs.length,
        initialIndex: tabs.isEmpty
            ? 0
            : videoDetailController.tabCtr.index.clamp(0, tabs.length - 1),
      );
    }

    Widget tabBar() {
      final flag = !needIndicator || tabs.length == 1;
      return TabBar(
        padding: .zero,
        dividerHeight: 0,
        labelPadding: .zero,
        dividerColor: Colors.transparent,
        controller: videoDetailController.tabCtr,
        indicator: flag ? const BoxDecoration() : null,
        labelColor: flag ? colorScheme.onSurface : null,
        labelStyle:
            TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
            const TextStyle(fontSize: 13),
        onTap: (value) {
          void animToTop() {
            if (onTap != null) {
              onTap();
              return;
            }
            String text = tabs[value];
            if (videoDetailController.isFileSource ||
                text == '简介' ||
                text == '相关视频') {
              videoDetailController.introScrollCtr?.animToTop();
            } else if (text.startsWith('评论')) {
              _replyScroll.animToTop();
            }
          }

          if (flag) {
            animToTop();
          } else if (!videoDetailController.tabCtr.indexIsChanging) {
            animToTop();
          }
        },
        tabs: tabs.map((text) {
          if (text == '评论') {
            return ListenableBuilder(
              listenable: Listenable.merge([_replyCount, _loadedReplyCount]),
              builder: (context, _) {
                final count = _loadedReplyCount.value ?? _replyCount.value;
                return Tab(
                  child: Text(
                    '评论${count == null ? '' : ' ${NumUtils.numFormat(count)}'}',
                    softWrap: false,
                    overflow: .visible,
                  ),
                );
              },
            );
          } else {
            return Tab(
              child: Text(text, softWrap: false, overflow: .visible),
            );
          }
        }).toList(),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SizedBox(
        height: 45,
        child: Row(
          children: [
            if (tabs.isEmpty)
              const Spacer()
            else
              Expanded(
                child: Align(
                  alignment: .centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 96.0 * tabs.length),
                    child: tabBar(),
                  ),
                ),
              ),
            SizedBox(
              height: 32,
              child: TextButton(
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(.zero),
                ),
                onPressed: videoDetailController.showShootDanmakuSheet,
                child: Text(
                  '发弹幕',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: 38,
              child: Obx(
                () {
                  final ctr = videoDetailController.plPlayerController;
                  final enableShowDanmaku = ctr.enableShowDanmaku.value;
                  return IconButton(
                    onPressed: () => ctr.toggleDanmakuVisibility(live: false),
                    icon: Icon(
                      size: 22,
                      enableShowDanmaku
                          ? CustomIcons.dm_on
                          : CustomIcons.dm_off,
                      color: enableShowDanmaku
                          ? colorScheme.secondary
                          : colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  Widget videoPlayer({required double width, required double height}) {
    final isFullScreen = this.isFullScreen;
    return Stack(
      key: videoDetailController.moreSettingsAnchorKey,
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            isAntiAlias: false,
          ),
        ),

        plPlayer(width: width, height: height),

        ValueListenableBuilder(
          valueListenable: videoDetailController.autoplayEnabled,
          builder: (context, autoplay, child) {
            if (!autoplay) {
              return Positioned.fill(
                child: GestureDetector(
                  onTap: handlePlay,
                  behavior: .opaque,
                  child: ValueListenableBuilder(
                    valueListenable: videoDetailController.cover,
                    builder: (context, cover, child) => NetworkImgLayer(
                      type: .emote,
                      quality: 60,
                      src: cover,
                      width: width,
                      height: height,
                      cacheWidth: true,
                      getPlaceHolder: () => Center(
                        child: Image.asset(
                          Assets.themed(
                            Assets.loading,
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        manualPlayerWidget(height),

        if (videoDetailController.plPlayerController.enableBlock ||
            videoDetailController.continuePlayingPart)
          Positioned(
            left: 16,
            bottom: isFullScreen ? max(75, maxHeight * 0.25) : 75,
            width: MediaQuery.textScalerOf(context).scale(120),
            child: AnimatedList(
              padding: EdgeInsets.zero,
              key: videoDetailController.listKey,
              reverse: true,
              shrinkWrap: true,
              initialItemCount: videoDetailController.listData.length,
              itemBuilder: (context, index, animation) {
                return videoDetailController.buildItem(
                  videoDetailController.listData[index],
                  animation,
                );
              },
            ),
          ),

        ValueListenableBuilder(
          valueListenable: videoDetailController.showSteinEdgeInfo,
          builder: (context, showChoices, child) {
            if (showChoices) {
              try {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: _steinChoicePadding(
                    child: Wrap(
                      spacing: 25,
                      runSpacing: 10,
                      children: videoDetailController
                          .steinEdgeInfo!
                          .edges!
                          .questions!
                          .first
                          .choices!
                          .map((item) {
                            return FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                shape: const RoundedRectangleBorder(
                                  borderRadius: .all(.circular(6)),
                                ),
                                backgroundColor: theme
                                    .colorScheme
                                    .secondaryContainer
                                    .withValues(alpha: 0.8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                ugcIntroController.onChangeEpisode(
                                  item,
                                  isStein: true,
                                );
                                videoDetailController.getSteinEdgeInfo(item.id);
                              },
                              child: Text(item.option!),
                            );
                          })
                          .toList(),
                    ),
                  ),
                );
              } catch (e, stackTrace) {
                logger.w(
                  'build stein edges: $e',
                  error: e,
                  stackTrace: stackTrace,
                );
                return const SizedBox.shrink();
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _steinChoicePadding({required Widget child}) {
    final controls = plPlayerController?.showControls;
    Widget buildPadding(bool visible) => Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: visible ? 75 : 16),
      child: child,
    );

    return controls == null
        ? buildPadding(false)
        : Obx(() => buildPadding(controls.value));
  }

  Widget localIntroPanel({
    bool needCtr = true,
  }) {
    return CustomScrollView(
      controller: needCtr
          ? videoDetailController.effectiveIntroScrollCtr
          : null,
      physics: !needCtr ? platformAlwaysClampingPhysics : null,
      key: const PageStorageKey(CommonIntroController),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 7, bottom: padding.bottom + 100),
          sliver: LocalIntroPanel(
            key: videoRelatedKey,
            controller: localIntroController,
          ),
        ),
      ],
    );
  }

  Widget videoIntro({
    double? width,
    double? height,
    bool? isHorizontal,
    bool needRelated = true,
    bool needCtr = true,
    bool pgcHeaderOnly = false,
    bool pgcShowHeader = true,
    Key? pageStorageKey,
  }) {
    if (videoDetailController.isFileSource) {
      return localIntroPanel(needCtr: needCtr);
    }

    Widget child = CustomScrollView(
      key: pageStorageKey ?? const PageStorageKey(CommonIntroController),
      controller: needCtr
          ? videoDetailController.effectiveIntroScrollCtr
          : null,
      physics: !needCtr ? platformAlwaysClampingPhysics : null,
      slivers: [
        if (videoDetailController.isUgc) ...[
          UgcIntroPanel(
            key: videoIntroKey,
            controller: ugcIntroController,
            showAiBottomSheet: showAiBottomSheet,
            showEpisodes: showEpisodes,
            onShowMemberPage: onShowMemberPage,
            isPortrait: isPortrait,
            isHorizontal: isHorizontal ?? width! / height! >= kScreenRatio,
          ),
          if (needRelated && videoDetailController.showRelatedVideo) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: Style.safeSpace,
                ),
                child: Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: colorScheme.outline.withValues(alpha: .08),
                ),
              ),
            ),
            RelatedVideoPanel(key: videoRelatedKey, query: _relatedQuery),
          ],
        ] else
          PgcIntroPage(
            controller: pgcIntroController,
            cid: videoDetailController.cid.value,
            showEpisodes: showEpisodes,
            showIntroDetail: showIntroDetail,
            maxWidth: width ?? maxWidth,
            isLandscape: !isPortrait,
            showHeader: pgcShowHeader,
            headerOnly: pgcHeaderOnly,
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                (videoDetailController.isPlayAll && !isPortrait
                    ? 80
                    : Style.safeSpace) +
                padding.bottom,
          ),
        ),
      ],
    );

    if (videoDetailController.isPlayAll) {
      child = IntroLayout(
        body: child,
        playlist: Padding(
          padding: .only(left: 12, right: 12, bottom: 12 + padding.bottom),
          child: Material(
            type: .transparency,
            child: InkWell(
              onTap: () => videoDetailController.showMediaListPanel(context),
              borderRadius: const .all(.circular(14)),
              child: Container(
                height: 54,
                padding: const .symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.95),
                  borderRadius: const .all(.circular(14)),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    const Icon(Icons.playlist_play, size: 24),
                    Expanded(
                      child: Text(
                        videoDetailController.watchLaterTitle,
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: .bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return KeepAliveWrapper(child: child);
  }

  Widget get seasonPanel {
    final videoDetail = ugcIntroController.videoDetail.value;
    return KeepAliveWrapper(
      child: Column(
        children: [
          if ((videoDetail.pages?.length ?? 0) > 1)
            if (videoDetail.ugcSeason != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: PagesPanel(
                  ugcIntroController: ugcIntroController,
                  bvid: ugcIntroController.bvid,
                  showEpisodes: showEpisodes,
                ),
              )
            else
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    videoDetailController.episodeSelection,
                    videoDetailController.cover,
                  ]),
                  builder: (context, child) => EpisodePanel(
                    enableSlide: false,
                    ugcIntroController: videoDetailController.isUgc
                        ? ugcIntroController
                        : null,
                    type: EpisodeType.part,
                    list: [videoDetail.pages!],
                    cover: videoDetailController.cover.value,
                    bvid: videoDetailController.bvid,
                    aid: videoDetailController.aid,
                    cid: videoDetailController.cid.value,
                    isReversed: videoDetail.isPageReversed,
                    onChangeEpisode: videoDetailController.isUgc
                        ? ugcIntroController.onChangeEpisode
                        : pgcIntroController.onChangeEpisode,
                    showTitle: false,
                    isSupportReverse: videoDetailController.isUgc,
                    onReverse: () => onReversePlay(isSeason: false),
                  ),
                ),
              ),
          if (videoDetail.ugcSeason != null) ...[
            if ((videoDetail.pages?.length ?? 0) > 1) ...[
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.1),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ValueListenableBuilder(
                valueListenable: introController.videoDetail,
                builder: (context, detail, child) => SeasonPanel(
                  key: ValueKey(detail),
                  canTap: false,
                  showEpisodes: showEpisodes,
                  ugcIntroController: ugcIntroController,
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  videoDetailController.episodeSelection,
                  videoDetailController.seasonIndex,
                  videoDetailController.cover,
                ]),
                builder: (context, child) => EpisodePanel(
                  enableSlide: false,
                  ugcIntroController: videoDetailController.isUgc
                      ? ugcIntroController
                      : null,
                  type: EpisodeType.season,
                  initialTabIndex: videoDetailController.seasonIndex.value,
                  cover: videoDetailController.cover.value,
                  seasonId: videoDetail.ugcSeason!.id,
                  list: videoDetail.ugcSeason!.sections!,
                  bvid: videoDetailController.bvid,
                  aid: videoDetailController.aid,
                  cid: videoDetailController.seasonCid ?? 0,
                  isReversed: ugcIntroController
                      .videoDetail
                      .value
                      .ugcSeason!
                      .sections![videoDetailController.seasonIndex.value]
                      .isReversed,
                  onChangeEpisode: videoDetailController.isUgc
                      ? ugcIntroController.onChangeEpisode
                      : pgcIntroController.onChangeEpisode,
                  showTitle: false,
                  isSupportReverse: videoDetailController.isUgc,
                  onReverse: () => onReversePlay(isSeason: true),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget videoReplyPanel({bool isNested = false}) => ValueListenableBuilder(
    valueListenable: _replyTarget,
    builder: (context, target, _) => target == null
        ? const SizedBox.shrink()
        : Consumer(
            builder: (context, ref, _) {
              final query = (
                owner: _replyOwner,
                target: target.target,
                thread: null,
              );
              ref.listen(
                commentsProvider(query).select((state) => state.count),
                (_, count) {
                  if (mounted && _replyTarget.value == target) {
                    _loadedReplyCount.value = count < 0 ? null : count;
                  }
                },
              );
              bool current() => mounted && _replyTarget.value == target;
              return VideoReplyPanel(
                key: videoReplyPanelKey,
                isNested: isNested,
                videoTools: (
                  durationMilliseconds: () =>
                      current() ? videoDetailController.commentDuration : null,
                  position: () => current()
                      ? videoDetailController.playedTime ?? Duration.zero
                      : null,
                  seek: (position) =>
                      current() && videoDetailController.seekFromPage(position),
                  capture: () =>
                      current() ? videoDetailController.commentFrame() : null,
                  share: (reply) =>
                      current() ? _videoCommentShare(reply) : null,
                ),
                query: query,
                sourceId: IdUtils.av2bv(target.aid),
                writeTarget: (oid: target.aid, type: target.target.type),
                targetIsCurrent: current,
                scrollController: _replyScroll,
              );
            },
          ),
  );

  CommentVideoShare _videoCommentShare(CommentReply reply) {
    final hasRoot = reply.rootId != null;
    final root = hasRoot ? reply.root : reply.id;
    final oid = reply.oid;
    final secondary = hasRoot ? '&comment_secondary_id=${reply.id}' : '';
    final url =
        'https://www.bilibili.com/video/av$oid?comment_on=1&comment_root_id=$root$secondary';
    if (videoDetailController.isFileSource) {
      return (
        url: url,
        cover: null,
        title: null,
        published: null,
        author: null,
      );
    }
    if (videoDetailController.isUgc) {
      final intro = ugcIntroController;
      final detail = intro.videoDetail.value;
      final part = detail.pages?.indexWhere(
        (item) => item.cid == intro.cid.value,
      );
      return (
        url: part != null && part > 0 ? '$url&p=${part + 1}' : url,
        cover: detail.pic,
        title: detail.title,
        published: detail.pubdate,
        author: detail.owner?.name,
      );
    }
    try {
      final intro = pgcIntroController;
      final pgc = intro.pgcItem;
      final episode = pgc.episodes?.firstWhereOrNull(
        (episode) => episode.cid == intro.cid.value,
      );
      if (episode != null) {
        final anchor = hasRoot ? 'anchor=${reply.id}&' : '';
        return (
          url:
              'bilibili://comment/detail/${reply.type.toInt()}/$oid/$root/'
              '?${anchor}enterUri=bilibili://pgc/season/ep/${intro.epId}',
          cover: episode.cover,
          title:
              episode.shareCopy ??
              '${pgc.title} ${episode.showTitle ?? episode.longTitle ?? ''}',
          published: episode.pubTime,
          author: pgc.upInfo?.uname,
        );
      }
    } on Error catch (_) {}
    return (url: url, cover: null, title: null, published: null, author: null);
  }

  // ai总结
  void showAiBottomSheet() {
    videoDetailController.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => AiConclusionPanel(
        item: ugcIntroController.aiConclusionResult!,
        onSeek: videoDetailController.seekFromPage,
      ),
    );
  }

  void showIntroDetail(
    PgcInfoModel videoDetail,
    List<VideoTagItem>? videoTags, [
    bool openReviews = false,
  ]) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => PgcIntroPanel(
        item: videoDetail,
        videoTags: videoTags,
        openReviews: openReviews,
      ),
    );
  }

  void showEpisodes([
    int? index,
    UgcSeason? season,
    List<ugc.BaseEpisodeItem>? episodes,
    String? bvid,
    int? aid,
    int? cid,
  ]) {
    assert((cid == null) == (bvid == null));
    final isFullScreen = this.isFullScreen;
    if (cid == null) {
      videoDetailController.showMediaListPanel(context);
      return;
    }
    Widget listSheetContent({bool enableSlide = true}) => EpisodePanel(
      ugcIntroController: videoDetailController.isUgc
          ? ugcIntroController
          : null,
      type: season != null
          ? EpisodeType.season
          : episodes is List<Part>
          ? EpisodeType.part
          : EpisodeType.pgc,
      cover: videoDetailController.cover.value,
      enableSlide: enableSlide,
      initialTabIndex: index ?? 0,
      bvid: bvid!,
      aid: aid,
      cid: cid,
      seasonId: season?.id,
      list: season != null ? season.sections! : [episodes],
      isReversed: !videoDetailController.isUgc
          ? null
          : season != null
          ? ugcIntroController
                .videoDetail
                .value
                .ugcSeason!
                .sections![videoDetailController.seasonIndex.value]
                .isReversed
          : ugcIntroController.videoDetail.value.isPageReversed,
      isSupportReverse: videoDetailController.isUgc,
      onChangeEpisode: videoDetailController.isUgc
          ? ugcIntroController.onChangeEpisode
          : pgcIntroController.onChangeEpisode,
      onClose: Get.back,
      onReverse: () {
        Get.back();
        onReversePlay(isSeason: season != null);
      },
    );
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = listSheetContent(enableSlide: false);
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: theme, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => listSheetContent(),
      );
    }
  }

  void onReversePlay({required bool isSeason}) {
    if (isSeason && videoDetailController.isPlayAll) {
      SmartDialog.showToast('当前为播放全部，合集不支持倒序');
      return;
    }

    final videoDetail = ugcIntroController.videoDetail.value;
    if (isSeason) {
      // reverse season
      final item = videoDetail
          .ugcSeason!
          .sections![videoDetailController.seasonIndex.value];
      item
        ..isReversed = !item.isReversed
        ..episodes = item.episodes!.reversed.toList();

      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController.refreshEpisodeOrder();
      } else {
        // switch to first episode
        final episode = ugcIntroController
            .videoDetail
            .value
            .ugcSeason!
            .sections![videoDetailController.seasonIndex.value]
            .episodes!
            .first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
          videoDetailController.seasonCid = episode.cid;
        } else {
          videoDetailController.refreshEpisodeOrder();
        }
      }
    } else {
      // reverse part
      videoDetail
        ..isPageReversed = !videoDetail.isPageReversed
        ..pages = videoDetail.pages!.reversed.toList();
      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController.refreshEpisodeOrder();
      } else {
        // switch to first episode
        final episode = videoDetail.pages!.first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
        } else {
          videoDetailController.refreshEpisodeOrder();
        }
      }
    }
  }

  void showViewPoints() {
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = ViewPointsPage(
        enableSlide: false,
        videoDetailController: videoDetailController,
        plPlayerController: plPlayerController,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: theme, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => ViewPointsPage(
          videoDetailController: videoDetailController,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }

  void onShowMemberPage(int? mid) {
    final host = videoDetailController.childKey.currentState;
    if (mid == null || host == null) return;
    final aid = videoDetailController.aid.toString();
    final bvid = videoDetailController.bvid;
    final AnchoredSpaceArchiveQuery query = (owner: this, mid: mid, aid: aid);
    if (_authorArchiveQuery?.mid != mid) {
      _authorSubscription?.close();
      _authorSubscription = ref.listenManual(
        videoAuthorProvider((owner: this, mid: mid)),
        (_, _) {},
      );
    }
    if (_authorArchiveQuery != query) {
      _authorArchiveQuery = query;
      _authorArchiveSubscription?.close();
      _authorArchiveSubscription = ref.listenManual(
        anchoredSpaceArchiveProvider(query),
        (_, _) {},
      );
    }
    host.showBottomSheet(
      constraints: const BoxConstraints(),
      dragHeight: 100,
      (context) => HorizontalMemberPage(
        key: ValueKey(query),
        query: query,
        bvid: bvid,
        onSelect: (video) {
          if (!mounted || _authorArchiveQuery != query) return;
          Get.back();
          ugcIntroController.onChangeEpisode(
            ugc.BaseEpisodeItem(
              bvid: video.bvid,
              cid: video.cid,
              cover: video.cover,
            ),
          );
        },
      ),
    );
  }
}
