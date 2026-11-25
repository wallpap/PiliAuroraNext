import 'dart:async';
import 'dart:math' show min;
import 'dart:ui';

import 'package:pili_aurora_next/features/community/presentation/comment_video_tools.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/core/types/pair.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/application/video_media_query.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/action_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/post_segment_model.dart';
import 'package:pili_aurora_next/features/sponsor_block/application/segment_model.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/audio_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_decode_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/playback/domain/playlist/media_list.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/result.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/episode.dart'
    as ugc;
import 'package:pili_aurora_next/features/playback/domain/video_detail/page.dart';
import 'package:pili_aurora_next/features/playback/domain/play_info/subtitle.dart';
import 'package:pili_aurora_next/features/playback/application/cast_media.dart';
import 'package:pili_aurora_next/features/playback/application/offline_progress.dart';
import 'package:pili_aurora_next/features/playback/application/subtitle_sources.dart';
import 'package:pili_aurora_next/features/playback/application/video_metadata.dart';
import 'package:pili_aurora_next/features/playback/application/video_playlist.dart';
import 'package:pili_aurora_next/features/sponsor_block/application/playback_preferences.dart';
import 'package:pili_aurora_next/features/playback/domain/interactive_video/data.dart';
import 'package:pili_aurora_next/pages/audio/view.dart';
import 'package:pili_aurora_next/pages/common/publish/publish_route.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/pages/sponsor_block/block_mixin.dart';
import 'package:pili_aurora_next/pages/video/download_panel/view.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/controller.dart';
import 'package:pili_aurora_next/pages/video/medialist/view.dart';
import 'package:pili_aurora_next/pages/video/playback_source.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/pages/video/note/view.dart';
import 'package:pili_aurora_next/pages/video/post_panel/view.dart';
import 'package:pili_aurora_next/pages/video/send_danmaku/view.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_source.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/heart_beat_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_status.dart';
import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/platform/network/connectivity.dart';
import 'package:pili_aurora_next/common/widgets/extensions/context_ext.dart';
import 'package:pili_aurora_next/common/widgets/extensions/nested_scroll_ext.dart';
import 'package:pili_aurora_next/common/layout/num_ext.dart';
import 'package:pili_aurora_next/common/widgets/extensions/size_ext.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/router/navigation_request.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/features/playback/application/audio_preferences.dart';
import 'package:pili_aurora_next/features/playback/application/video_preferences.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/services/diagnostics/report_error.dart';
import 'package:collection/collection.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart'
    show ExtendedNestedScrollViewState;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart' show Get, GetNavigation;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide Subtitle;

class VideoDetailController with BlockMixin {
  bool _closed = false;
  bool get isClosed => _closed;
  late final TickerProvider _vsync;
  CommonIntroController? introduction;
  UgcIntroController? get _ugcIntro => switch (introduction) {
    final UgcIntroController intro => intro,
    _ => null,
  };
  PgcIntroController? get _pgcIntro => switch (introduction) {
    final PgcIntroController intro => intro,
    _ => null,
  };

  /// 路由传参
  late final Map args;
  late String bvid;
  late int aid;
  final cid = ValueNotifier(0);
  final _episodeOrderRevision = ValueNotifier(0);
  late final episodeSelection = Listenable.merge([cid, _episodeOrderRevision]);

  void refreshEpisodeOrder() => _episodeOrderRevision.value++;
  int? epId;
  VoidCallback? onReplyTargetChanged;
  ValueChanged<int>? onReplyCount;
  CommentVideoFrame? commentFrame() {
    if (isClosed) return null;
    final bvid = this.bvid;
    final part = cid.value;
    final controller = plPlayerController;
    final player = controller.videoPlayerController;
    final owner = controller.activePlaybackOwner;
    if (player == null) return null;
    return (
      read: player.screenshot,
      isCurrent: () =>
          !isClosed &&
          this.bvid == bvid &&
          cid.value == part &&
          identical(player, controller.videoPlayerController) &&
          identical(owner, controller.activePlaybackOwner),
    );
  }

  int? get commentDuration {
    try {
      return data.timeLength;
    } catch (_) {
      return null;
    }
  }

  bool seekFromPage(Duration position) {
    if (isClosed || !playbackOwner.isActive) return false;
    unawaited(plPlayerController.seekTo(position, isSeek: false));
    return true;
  }

  int? seasonId;
  int? pgcType;
  late final String heroTag;
  final cover = ValueNotifier('');

  // 视频类型 默认投稿视频
  late final VideoType videoType;
  @override
  late final isUgc = videoType == VideoType.ugc;
  VideoType? _actualVideoType;

  // 页面来源 稍后再看 收藏夹
  late bool isPlayAll;
  late SourceType sourceType;
  late BiliDownloadEntryInfo entry;
  late bool isFileSource;
  VideoPlaylist? _playlist;
  List<MediaListItemModel> get mediaList => _playlist?.items.value ?? const [];
  late String watchLaterTitle;

  /// tabs相关配置
  late TabController tabCtr;

  // 请求返回的视频信息
  late PlayUrlModel data;
  final videoState = ValueNotifier(false);

  /// 播放器配置 画质 音质 解码格式
  final currentVideoQa = ValueNotifier<VideoQuality?>(null);
  final availableVideoQualities = ValueNotifier<Set<int>>(const {});
  AudioQuality? currentAudioQa;
  late VideoDecodeFormatType currentDecodeFormats;

  // 是否开始自动播放 存在多p的情况下，第二p需要为true
  final _autoPlay = ValueNotifier(VideoPreferences.autoplay);
  ValueListenable<bool> get autoplayEnabled => _autoPlay;

  final videoPlayerKey = GlobalKey();
  final moreSettingsAnchorKey = GlobalKey();
  final childKey = GlobalKey<MiniScaffoldState>();

  final plPlayerController = PlPlayerController.getInstance()
    ..brightness.value = -1;
  bool get setSystemBrightness => plPlayerController.setSystemBrightness;
  bool get removeSafeArea => plPlayerController.removeSafeArea;
  double get uiScale => plPlayerController.uiScale;

  late VideoItem firstVideo;
  NetworkSource? _networkSource;
  String? get videoUrl => _networkSource?.videoSource;
  String? get audioUrl =>
      _networkSource == null ? null : _networkSource!.audioSource ?? '';
  late final PlaybackOwner playbackOwner;
  ShutdownPlaybackBinding? _shutdownBinding;

  void _bindShutdownTimer() {
    if (!playbackOwner.isActive || _shutdownBinding?.isBound == true) return;
    _shutdownBinding = shutdownTimerService.bindPlayer(
      pause: plPlayerController.pause,
      isPlaying: () =>
          playbackOwner.isActive && plPlayerController.playerStatus.isPlaying,
    );
  }

  bool completeShutdownTimer() =>
      playbackOwner.isActive && (_shutdownBinding?.complete() ?? false);
  PlaybackPlan? _playbackPlan;
  int _sourceSelectionGeneration = 0;
  VideoMediaQuery? _videoQueryCancel;
  ({
    VideoPlaybackSource source,
    bool videoChanged,
    bool audioChanged,
    bool Function() isCurrent,
  })?
  _pendingSourceSelection;
  PlaybackInhibitorToken? _routeInhibitor;
  int _routePlaybackGeneration = 0;
  Duration? defaultST;
  Duration? playedTime;
  String playedTimePos(bool hasParams) {
    final pos = playedTime?.inMilliseconds;
    if (pos != null && pos > 0) {
      return '${hasParams ? '&' : '?'}t=${pos / 1000}';
    }
    return '';
  }

  // 亮度
  double? brightness;

  late final headerCtrKey = GlobalKey<TimeBatteryMixin>();

  // 预设的解码格式
  late List<VideoDecodeFormatType> preferCodecs = VideoPreferences.codecs();

  bool get showReply => isFileSource
      ? false
      : isUgc
      ? plPlayerController.showVideoReply
      : plPlayerController.showBangumiReply;

  bool get showRelatedVideo =>
      isFileSource ? false : plPlayerController.showRelatedVideo;

  ScrollController? introScrollCtr;
  ScrollController get effectiveIntroScrollCtr =>
      introScrollCtr ??= ScrollController();

  int? seasonCid;
  final seasonIndex = ValueNotifier(0);

  PlayerStatus? playerStatus;

  late final scrollKey = GlobalKey<ExtendedNestedScrollViewState>();
  final isVertical = ValueNotifier(false);
  final scrollRatio = ValueNotifier(0.0);

  void updateScrollRatio(double value) {
    if (!isClosed) scrollRatio.value = value;
  }

  ScrollController? _scrollCtr;
  ScrollController get scrollCtr => _scrollCtr ??= ScrollController();

  late bool isExpanding = false;
  late bool isCollapsing = false;

  late double minVideoHeight;
  late double maxVideoHeight;
  late double videoHeight;
  late double animHeight;

  AnimationController? animController;
  AnimationController get animationController =>
      animController ??= (AnimationController(
        vsync: _vsync,
        duration: const Duration(milliseconds: 200),
      )..addListener(_animListener));

  void refreshPage() {
    scrollKey.currentState?.refresh();
  }

  void _animListener() {
    if (animationController.isForwardOrCompleted) {
      _calcAnimHeight();
      refreshPage();
    }
  }

  void _calcAnimHeight() {
    if (isExpanding) {
      animHeight = clampDouble(
        videoHeight * animationController.value,
        kToolbarHeight,
        videoHeight,
      );
    } else if (isCollapsing) {
      animHeight = clampDouble(
        maxVideoHeight -
            (maxVideoHeight - minVideoHeight) * animationController.value,
        minVideoHeight,
        maxVideoHeight,
      );
    }
  }

  void animToTop() {
    scrollKey.currentState?.animToTop();
  }

  bool _needAnimOnDimensionChanged(bool isVertical) {
    if (isFullScreen) {
      if (PlatformUtils.isMobile) {
        plPlayerController.changeOrientation(isVertical: isVertical);
      }
      return false;
    }
    return true;
  }

  @pragma('vm:notify-debugger-on-exception')
  void _setVideoHeight() {
    try {
      var width = firstVideo.width;
      var height = firstVideo.height;
      if (width == null || height == null) {
        if (isUgc && !isFileSource) {
          final cid = this.cid.value;
          final part = _ugcIntro?.videoDetail.value.pages?.firstWhereOrNull(
            (e) => e.cid == cid,
          );
          if (part != null) {
            final dimension = part.dimension!;
            width = dimension.width!;
            height = dimension.height!;
          } else {
            return;
          }
        } else {
          return;
        }
      }
      final isVertical = height > width;
      if (_scrollCtr?.hasClients != true) {
        videoHeight = isVertical ? maxVideoHeight : minVideoHeight;
        if (this.isVertical.value != isVertical) {
          this.isVertical.value = isVertical;
          _needAnimOnDimensionChanged(isVertical);
        }
        return;
      }
      if (this.isVertical.value != isVertical) {
        this.isVertical.value = isVertical;
        double videoHeight = isVertical ? maxVideoHeight : minVideoHeight;
        if (this.videoHeight != videoHeight) {
          if (videoHeight > this.videoHeight) {
            // current minVideoHeight
            if (_needAnimOnDimensionChanged(isVertical)) {
              isExpanding = true;
              animationController.forward(
                from: (minVideoHeight - scrollCtr.offset) / maxVideoHeight,
              );
            }
            this.videoHeight = maxVideoHeight;
          } else {
            // current maxVideoHeight
            final currentHeight = (maxVideoHeight - scrollCtr.offset)
                .toPrecision(2);
            double minVideoHeightPrecise = minVideoHeight.toPrecision(2);
            if (currentHeight == minVideoHeightPrecise) {
              this.videoHeight = minVideoHeight;
              if (_needAnimOnDimensionChanged(isVertical)) {
                isExpanding = true;
                animationController.forward(from: 1);
              }
            } else if (currentHeight < minVideoHeightPrecise) {
              // expand
              if (_needAnimOnDimensionChanged(isVertical)) {
                isExpanding = true;
                animationController.forward(
                  from: currentHeight / minVideoHeight,
                );
              }
              this.videoHeight = minVideoHeight;
            } else {
              // collapse
              if (_needAnimOnDimensionChanged(isVertical)) {
                isCollapsing = true;
                animationController.forward(
                  from: scrollCtr.offset / (maxVideoHeight - minVideoHeight),
                );
              }
              this.videoHeight = minVideoHeight;
            }
          }
        }
      } else {
        if (scrollCtr.offset != 0) {
          isExpanding = true;
          animationController.forward(from: 1 - scrollCtr.offset / videoHeight);
        }
      }
    } catch (_) {}
  }

  final isLoginVideo = AccountScope.captureVideo().account.isLogin;

  void cacheLocalProgress() {
    final position = plPlayerController.playerStatus.isCompleted
        ? entry.totalTimeMilli
        : playedTime?.inMilliseconds;
    if (position != null) {
      unawaited(OfflineProgress.record(cid.value, position));
    }
  }

  void initFileSource(BiliDownloadEntryInfo entry, {bool isInit = true}) {
    this.entry = entry;
    firstVideo = VideoItem(
      id: entry.preferedVideoQuality,
      quality: VideoQuality.fromCode(entry.preferedVideoQuality),
      width: entry.ep?.width ?? entry.pageData?.width ?? 1,
      height: entry.ep?.height ?? entry.pageData?.height ?? 1,
    );
    defaultST = OfflineProgress.resume(cid.value, entry.totalTimeMilli);
    data = PlayUrlModel(timeLength: entry.totalTimeMilli);
    _setVideoHeight();
  }

  void open(Map arguments, TickerProvider vsync) {
    _vsync = vsync;
    playbackOwner = plPlayerController.attachPlaybackOwner();
    _bindShutdownTimer();
    args = arguments;
    videoType = args['videoType'];
    if (videoType == VideoType.pgc) {
      if (!isLoginVideo) {
        _actualVideoType = VideoType.ugc;
      }
    } else if (args['pgcApi'] == true) {
      _actualVideoType = VideoType.pgc;
    }

    bvid = args['bvid'];
    aid = args['aid'];
    cid.value = args['cid'];
    epId = args['epId'];
    seasonId = args['seasonId'];
    pgcType = args['pgcType'];
    heroTag = args['heroTag'];
    cover.value = args['cover'] ?? '';
    isVertical.value = args['isVertical'] ?? false;

    sourceType = args['sourceType'] ?? SourceType.normal;
    isFileSource = sourceType == SourceType.file;
    isPlayAll = sourceType != SourceType.normal && !isFileSource;
    if (isFileSource) {
      initFileSource(args['entry']);
      if (args['progress'] case final int progress) {
        defaultST = Duration(milliseconds: progress);
      }
    } else if (isPlayAll) {
      watchLaterTitle = args['favTitle'];
      _playlist = VideoPlaylist(
        source: sourceType,
        id: args['mediaId'] ?? -1,
        type: args['mediaType'] ?? sourceType.mediaType!,
        count: args['count'],
        descending: args['desc'],
        continueFromAnchor: args['isContinuePlaying'] == true,
        anchor: args['oid'],
        sortField: args['sortField'],
        ownedFavorite: args['isOwner'] == true,
      );
      getMediaList();
    }

    tabCtr = TabController(
      length: 2,
      vsync: _vsync,
      initialIndex: VideoPreferences.openCommentsFirst ? 1 : 0,
    );
  }

  Future<void> getMediaList({
    bool isReverse = false,
    bool isLoadPrevious = false,
  }) async {
    final result = await _playlist?.load(
      previous: isLoadPrevious,
      reverse: isReverse,
    );
    if (isClosed) return;
    if (result case Success(response: final episode?)) {
      _ugcIntro?.onChangeEpisode(episode);
    } else if (result case Error()) {
      result.toast();
    }
  }

  void showMediaListPanel(BuildContext context) {
    final playlist = _playlist;
    if (playlist == null) return;
    if (mediaList.isNotEmpty) {
      Widget panel() => MediaListPanel(
        mediaList: playlist.items,
        onChangeEpisode: (episode) {
          _ugcIntro?.onChangeEpisode(episode);
        },
        panelTitle: watchLaterTitle,
        bvid: bvid,
        loadMoreMedia: getMediaList,
        desc: playlist.descending,
        onReverse: () => getMediaList(isReverse: true),
        loadPrevious: playlist.continueFromAnchor
            ? () => getMediaList(isLoadPrevious: true)
            : null,
        onDelete: playlist.canRemove
            ? (item) async {
                final result = await playlist.remove(item);
                if (isClosed || result == null) return;
                if (result.isSuccess) {
                  SmartDialog.showToast(
                    sourceType == SourceType.watchLater ? '已移除稍后再看' : '取消收藏',
                  );
                } else {
                  result.toast();
                }
              }
            : null,
      );
      if (plPlayerController.isFullScreen.value || showVideoSheet) {
        PageUtils.showVideoBottomSheet(
          context,
          child: plPlayerController.darkVideoPage
              ? Theme(data: ThemeUtils.darkTheme, child: panel())
              : panel(),
        );
      } else {
        childKey.currentState?.showBottomSheet(
          constraints: const BoxConstraints(),
          (context) => panel(),
        );
      }
    } else {
      getMediaList();
    }
  }

  bool isPortrait = true;

  bool get horizontalScreen => plPlayerController.horizontalScreen;

  bool get showVideoSheet =>
      (!horizontalScreen && !isPortrait) || plPlayerController.isDesktopPip;

  @override
  final ValueNotifier<String> videoLabel = ValueNotifier('');
  @override
  int? get timeLength => data.timeLength;
  @override
  BlockConfigMixin get blockConfig => plPlayerController;
  @override
  Player? get player => plPlayerController.videoPlayerController;
  @override
  Future<void> applyBlockMute(bool muted) async {
    if (playbackOwner.isActive) await playbackOwner.setMuted(muted);
  }

  @override
  bool get isFullScreen => plPlayerController.isFullScreen.value;
  @override
  bool get autoPlay => _autoPlay.value;
  set autoPlay(bool value) => _autoPlay.value = value;
  @override
  bool get preInitPlayer => plPlayerController.preInitPlayer;
  @override
  int get currPosInMilliseconds =>
      defaultST?.inMilliseconds ?? plPlayerController.positionInMilliseconds;
  @override
  Future<void> seekTo(Duration duration, {required bool isSeek}) =>
      plPlayerController.seekTo(duration, isSeek: isSeek);

  @override
  Widget buildItem(Object item, Animation<double> animation) {
    final theme = ThemeUtils.theme;
    return Align(
      alignment: Alignment.centerLeft,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(-1.0, 0.0),
            end: Offset.zero,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: GestureDetector(
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              if (details.delta.dx < 0) {
                onRemoveItem(listData.indexOf(item), item);
              }
            },
            child: SearchText(
              bgColor: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.8,
              ),
              textColor: theme.colorScheme.onSecondaryContainer,
              padding: const .symmetric(horizontal: 8, vertical: 4),
              fontSize: 14,
              text: item is SegmentModel
                  ? '跳过: ${item.segmentType.shortTitle}'
                  : '上次看到第${(item as int) + 1}P，点击跳转',
              onTap: (_) {
                if (item is int) {
                  try {
                    final ugcIntroController = _ugcIntro!;
                    Part part =
                        ugcIntroController.videoDetail.value.pages![item];
                    ugcIntroController.onChangeEpisode(part);
                    SmartDialog.showToast('已跳至第${item + 1}P');
                  } catch (e, stackTrace) {
                    logger.w('$e', error: e, stackTrace: stackTrace);
                    SmartDialog.showToast('跳转失败');
                  }
                  onRemoveItem(listData.indexOf(item), item);
                } else if (item is SegmentModel) {
                  onSkip(item, isSeek: false);
                  onRemoveItem(listData.indexOf(item), item);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  ({int mode, int fontSize, Color color})? dmConfig;
  String? savedDanmaku;

  /// 发送弹幕
  Future<void> showShootDanmakuSheet() async {
    if (plPlayerController.dmState.contains(cid.value)) {
      SmartDialog.showToast('UP主已关闭弹幕');
      return;
    }
    final isPlaying =
        _autoPlay.value && plPlayerController.playerStatus.isPlaying;
    if (isPlaying) {
      await plPlayerController.pause();
    }
    await Get.key.currentState!.push(
      PublishRoute(
        pageBuilder: (buildContext, animation, secondaryAnimation) {
          final child = SendDanmakuPanel(
            cid: cid.value,
            bvid: bvid,
            progress: plPlayerController.positionInMilliseconds,
            initialValue: savedDanmaku,
            onSave: (danmaku) => savedDanmaku = danmaku,
            onSuccess: (danmakuModel) {
              savedDanmaku = null;
              plPlayerController.danmakuDisplay?.echo?.call(
                danmakuModel,
                plPlayerController.positionInMilliseconds * 1000,
              );
            },
            dmConfig: dmConfig,
            onSaveDmConfig: (dmConfig) => this.dmConfig = dmConfig,
          );
          if (plPlayerController.darkVideoPage) {
            return Theme(data: ThemeUtils.darkTheme, child: child);
          }
          return child;
        },
      ),
    );
    if (isPlaying) {
      plPlayerController.play();
    }
  }

  VideoItem findVideoByQa(int qa, {bool setCodecs = false}) {
    final video = VideoPlaybackSource.selectVideoTrack(
      data.dash!.video!,
      quality: qa,
      codec: currentDecodeFormats,
      preferredCodecs: preferCodecs,
    );
    if (setCodecs) {
      currentDecodeFormats = VideoDecodeFormatType.fromString(video.codecs!);
    }
    return video;
  }

  void _applyPlaybackSource(VideoPlaybackSource selection) {
    _networkSource = selection.source;
    firstVideo = selection.video;
    currentVideoQa.value = selection.video.quality;
    currentDecodeFormats = selection.codec;
    currentAudioQa = selection.audio == null
        ? null
        : AudioQuality.fromCode(selection.audio!.id);
  }

  bool get playbackSourceMatchesSelection => _samePlaybackSource(
    plPlayerController.currentPlaybackPlan,
    _playbackPlan,
  );

  static bool _samePlaybackSource(PlaybackPlan? a, PlaybackPlan? b) {
    const equality = ListEquality<String>();
    return a != null &&
        b != null &&
        a.contentKey == b.contentKey &&
        equality.equals(a.source.videoCandidates, b.source.videoCandidates) &&
        equality.equals(a.source.audioCandidates, b.source.audioCandidates);
  }

  /// 切换质量沿用播放意图，原生 open 期间的短暂暂停不改变用户选择。
  Future<LoadResult> updatePlayer({
    VideoQuality? videoQuality,
    AudioQuality? audioQuality,
    VideoDecodeFormatType? codec,
  }) async {
    if (isClosed || !playbackOwner.isActive) {
      return const LoadResult.inactive();
    }
    final pending = _pendingSourceSelection;
    final previous = pending?.isCurrent() == true ? pending : null;
    final quality =
        videoQuality ?? previous?.source.video.quality ?? currentVideoQa.value;
    if (quality == null || isFileSource || _networkSource == null) {
      return const LoadResult.noMedia();
    }
    if (playbackOwner.isQuerying) return const LoadResult.deferred();
    final generation = ++_sourceSelectionGeneration;
    final identity = (bvid, cid.value, epId, seasonId);
    final sourceData = data;
    final accountOwner = AccountScope.captureVideo();
    final ownsPlayback = playbackOwner.guard();
    bool valid() =>
        !isClosed &&
        ownsPlayback() &&
        generation == _sourceSelectionGeneration &&
        identity == (bvid, cid.value, epId, seasonId) &&
        identical(data, sourceData) &&
        accountOwner.isCurrent;
    try {
      final selection = VideoPlaybackSource.resolve(
        sourceData,
        videoQuality: quality.code,
        audioQuality:
            audioQuality?.code ??
            previous?.source.audio?.id ??
            currentAudioQa?.code ??
            plPlayerController.cacheAudioQa,
        codec: codec ?? previous?.source.codec ?? currentDecodeFormats,
        preferredCodecs: preferCodecs,
      );
      final videoChanged =
          videoQuality != null || previous?.videoChanged == true;
      final audioChanged =
          audioQuality != null || previous?.audioChanged == true;
      // 连续调整画质和音质时沿用仍有效的目标；确认值仍等最新加载完成。
      _pendingSourceSelection = (
        source: selection,
        videoChanged: videoChanged,
        audioChanged: audioChanged,
        isCurrent: valid,
      );
      _rememberPlaybackState();
      final configuration = plPlayerController.capturePlaybackConfiguration(
        live: false,
        source: selection.source,
        mediaVolume: volume,
      );
      final plan = _buildPlaybackPlan(
        selection.source,
        configuration,
        video: selection.video,
      );
      final result = await loadPlaybackPlanForRoute(
        plan,
        start: PlaybackStartPolicy.preserve,
        onReady: () {},
      );
      if (!valid()) return const LoadResult.superseded();
      if (result.outcome == LoadOutcome.ready) {
        // 页面选择与默认偏好只确认真实加载成功的来源，失败保留原选择以便重试。
        _applyPlaybackSource(selection);
        _playbackPlan = plan;
        if (videoChanged) {
          plPlayerController.cacheVideoQa = selection.video.quality.code;
        }
        if (audioChanged && selection.audio != null) {
          plPlayerController.cacheAudioQa = selection.audio!.id;
        }
        videoState.value = true;
        unawaited(setSubtitle(vttSubtitlesIndex.value));
        afterPlaybackReady(valid);
        defaultST = null;
      } else if (result.outcome == LoadOutcome.failed ||
          result.outcome == LoadOutcome.noMedia) {
        SmartDialog.showToast('播放源切换失败，请重试');
      }
      return result;
    } catch (error, stackTrace) {
      final failure = PlaybackFailure(
        category: PlaybackFailureCategory.capability,
        operation: 'selectSource',
        stage: plPlayerController.currentPlaybackSnapshot.stage,
        recoverable: true,
        cause: '播放源选择或加载失败（${error.runtimeType}）',
      );
      logger.w('切换播放源失败', error: error.runtimeType, stackTrace: stackTrace);
      if (!valid()) return const LoadResult.superseded();
      SmartDialog.showToast('播放源切换失败，请重试');
      return LoadResult.failed(failure);
    } finally {
      if (generation == _sourceSelectionGeneration) {
        _pendingSourceSelection = null;
      }
    }
  }

  void _rememberPlaybackState() {
    _autoPlay.value = plPlayerController.currentPlaybackSnapshot.intent.playing;
    playedTime = plPlayerController.playbackResumePosition ?? playedTime;
  }

  bool _shouldInitializePlayer({bool force = false}) =>
      force || _autoPlay.value || plPlayerController.preInitPlayer;

  Future<void>? _initPlayerIfNeeded(
    bool autoFullScreenFlag, {
    bool force = false,
  }) {
    if (_shouldInitializePlayer(force: force)) {
      return playerInit(
        autoFullScreenFlag: autoFullScreenFlag && _autoPlay.value,
      );
    }
    return null;
  }

  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
  }) async {
    if (isClosed || !playbackOwner.isActive) {
      return;
    }
    _sourceSelectionGeneration++;
    final identity = (bvid, cid.value, epId, seasonId);
    final source = isFileSource
        ? FileSource(
            dir: args['dirPath'],
            typeTag: entry.typeTag!,
            isMp4: entry.mediaType == 1,
            hasDashAudio: entry.hasDashAudio,
          )
        : _networkSource;
    if (source == null) return;
    final configuration = plPlayerController.capturePlaybackConfiguration(
      live: false,
      source: source,
      mediaVolume: volume,
    );
    final plan = _buildPlaybackPlan(source, configuration);
    _playbackPlan = plan;
    bool valid() =>
        !isClosed &&
        playbackOwner.isActive &&
        identity == (bvid, cid.value, epId, seasonId) &&
        (isFileSource || identical(source, _networkSource));
    final result = await plPlayerController.loadPlaybackPlan(
      owner: playbackOwner,
      plan: plan,
      // 新页面按自动播放偏好起播；同一内容重载沿用会话意图。
      start:
          autoplay == null &&
              plPlayerController.currentPlaybackContentKey == plan.contentKey
          ? PlaybackStartPolicy.preserve
          : (autoplay ?? _autoPlay.value)
          ? PlaybackStartPolicy.play
          : PlaybackStartPolicy.pause,
      live: false,
      isVertical: isVertical.value,
      aid: aid,
      bvid: bvid,
      cid: cid.value,
      epid: isUgc ? null : epId,
      seasonId: isUgc ? null : seasonId,
      pgcType: isUgc ? null : pgcType,
      videoType: videoType,
      onReady: () {
        if (!valid()) return;
        videoState.value = true;
        unawaited(setSubtitle(vttSubtitlesIndex.value));
      },
      autoFullScreenFlag: autoFullScreenFlag,
    );

    if (!valid() || result.outcome != LoadOutcome.ready) return;
    afterPlaybackReady(valid);
    defaultST = null;
  }

  PlaybackPlan _buildPlaybackPlan(
    DataSource source,
    PlaybackConfiguration configuration, {
    VideoItem? video,
  }) {
    Duration? seek = defaultST ?? playedTime;
    if (seek == .zero) seek = null;
    seek ??= getFirstSegment();
    final contentKey = isFileSource
        ? 'file:${cid.value}'
        : isUgc
        ? 'ugc:$bvid:${cid.value}'
        : 'pgc:${seasonId ?? 0}:${epId ?? 0}:${cid.value}';
    return plPlayerController.createPlaybackPlan(
      contentKey: contentKey,
      source: source,
      configuration: configuration,
      timelineKind: isFileSource
          ? PlaybackTimelineKind.local
          : PlaybackTimelineKind.onDemand,
      seekPolicy: PlaybackSeekPolicy.allowed,
      duration: data.timeLength == null
          ? null
          : Duration(milliseconds: data.timeLength!),
      startPosition: seek,
      reloadPosition: playedTime,
      metadata: PlaybackMetadataHint(
        trust: PlaybackMetadataTrust.sourceHint,
        width: (video ?? firstVideo).width,
        height: (video ?? firstVideo).height,
      ),
      mediaVolume: volume,
    );
  }

  void afterPlaybackReady(bool Function() valid) {
    if (!valid() || isFileSource) return;
    if (plPlayerController.enableBlock) initSkip();
    if (vttSubtitlesIndex.value == -1) {
      _queryPlayInfo(isCurrent: valid);
    }
    if (plPlayerController.showDmChart && dmTrend.value == null) {
      _getDmTrend(isCurrent: valid);
    }
  }

  Future<LoadResult> submitPlaybackQuery(
    Future<PlaybackPlan?> Function(PlaybackQuery) resolve, {
    required PlaybackStartPolicy start,
    bool Function()? shouldLoad,
  }) => playbackOwner.query(resolve, start: start, shouldLoad: shouldLoad);

  Future<LoadResult> loadPlaybackPlanForRoute(
    PlaybackPlan plan, {
    required PlaybackStartPolicy start,
    required void Function() onReady,
  }) => plPlayerController.loadPlaybackPlan(
    owner: playbackOwner,
    plan: plan,
    start: start,
    live: false,
    isVertical: isVertical.value,
    aid: aid,
    bvid: bvid,
    cid: cid.value,
    epid: isUgc ? null : epId,
    seasonId: isUgc ? null : seasonId,
    pgcType: isUgc ? null : pgcType,
    videoType: videoType,
    onReady: onReady,
  );

  Future<CommandResult> applyPlaybackSubtitleTrack(
    PlaybackSubtitleTrack? track,
  ) => playbackOwner.setSubtitleTrack(track);

  void holdPlaybackForRoute() {
    _routePlaybackGeneration++;
    _sourceSelectionGeneration++;
    _pendingSourceSelection = null;
    playbackOwner.invalidateRequests();
    final snapshot = plPlayerController.currentPlaybackSnapshot;
    final currentPlan = plPlayerController.currentPlaybackPlan;
    final confirmedPlan = _playbackPlan;
    // 会话计划可能已指向尚未成功的选择；返回页面时仍恢复已确认来源。
    final plan =
        currentPlan != null &&
            confirmedPlan != null &&
            currentPlan.contentKey == confirmedPlan.contentKey &&
            !_samePlaybackSource(currentPlan, confirmedPlan)
        ? confirmedPlan
        : currentPlan;
    if (plan != null &&
        confirmedPlan != null &&
        plan.contentKey == confirmedPlan.contentKey) {
      final position = plPlayerController.isCompleted
          ? Duration.zero
          : plPlayerController.videoPlayerController?.state.position ??
                playedTime ??
                snapshot.actual.position;
      if (position != null) {
        _playbackPlan = PlaybackPlan(
          contentKey: plan.contentKey,
          source: plan.source,
          timeline: plan.timeline,
          configuration: snapshot.configuration.desired,
          startPosition: position,
          reloadPosition: position,
          metadata: plan.metadata,
        );
      }
    }
    _routeInhibitor ??= playbackOwner.acquireInhibitor(
      PlaybackInhibitorSource.system,
    );
  }

  Future<void> restorePlaybackAfterRoute() async {
    if (isClosed) return;
    final generation = ++_routePlaybackGeneration;
    plPlayerController.activatePlaybackOwner(playbackOwner);
    _bindShutdownTimer();
    final plan = _playbackPlan;
    final token = _routeInhibitor;
    final identity = (bvid, cid.value, epId, seasonId);
    final ownsPlayback = playbackOwner.guard();
    bool canConfirm() =>
        !isClosed &&
        generation == _routePlaybackGeneration &&
        ownsPlayback() &&
        identity == (bvid, cid.value, epId, seasonId);

    try {
      if (plan != null) {
        final result = await loadPlaybackPlanForRoute(
          plan,
          start: PlaybackStartPolicy.preserve,
          onReady: () {
            if (!canConfirm()) return;
            videoState.value = true;
            unawaited(setSubtitle(vttSubtitlesIndex.value));
          },
        );
        if (result.outcome == LoadOutcome.ready && canConfirm()) {
          videoState.value = true;
        }
      } else if (isFileSource) {
        await _initPlayerIfNeeded(false);
      } else {
        await queryVideoUrl(startPolicy: PlaybackStartPolicy.preserve);
      }
    } finally {
      if (token != null &&
          generation == _routePlaybackGeneration &&
          identical(token, _routeInhibitor)) {
        _routeInhibitor = null;
        await playbackOwner.releaseInhibitor(token);
      }
    }
  }

  /*
   * Page business state is prepared in the query resolver; PlaybackOwner.query
   * accepts exactly one request and the resolved immutable plan is submitted
   * by the session itself.
   */

  bool get isQuerying => playbackOwner.isQuerying;

  bool Function() _mediaGuard() {
    final identity = (bvid, cid.value);
    final source = _networkSource;
    final ownsPlayback = playbackOwner.guard();
    return () =>
        !isClosed &&
        ownsPlayback() &&
        identity == (bvid, cid.value) &&
        identical(source, _networkSource);
  }

  final languages = ValueNotifier<List<LanguageItem>?>(null);
  final currLang = ValueNotifier<String?>(null);
  void setLanguage(String language) {
    if (currLang.value == language) return;
    if (!isLoginVideo) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    currLang.value = language;
    queryVideoUrl(fromReset: true);
  }

  VideoMediaQuery _captureVideoQuery(Account account) => VideoMediaQuery(
    account: account,
    cid: cid.value,
    bvid: bvid,
    episode: epId,
    season: seasonId,
    type: _actualVideoType ?? videoType,
    language: currLang.value,
    tryLook: plPlayerController.tryLook,
    voiceBalance: plPlayerController.enableAudioNormalization,
  );

  Future<bool> _supplementVideoQualities(
    PlayUrlModel response,
    int quality,
    Future<LoadingState<PlayUrlModel>> Function(int) fetch,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return false;
    final result = await fetch(quality);
    if (result case Success(response: final supplement) when isCurrent()) {
      if (supplement.dash?.video case final tracks? when tracks.isNotEmpty) {
        response.dash!.video!.merge(tracks);
        return true;
      }
    }
    return false;
  }

  Volume? volume;

  Future<void> retryPlayback() async {
    if (isClosed || !playbackOwner.isActive || plPlayerController.processing) {
      return;
    }
    if (isFileSource && plPlayerController.currentPlaybackPlan != null) {
      _rememberPlaybackState();
      defaultST = null;
    }
    await queryVideoUrl(
      fromReset: true,
      startPolicy: PlaybackStartPolicy.preserve,
    );
  }

  // 视频链接
  Future<void> queryVideoUrl({
    bool fromReset = false,
    bool autoFullScreenFlag = false,
    PlaybackStartPolicy? startPolicy,
  }) async {
    if (isClosed || !playbackOwner.isActive) return;
    _sourceSelectionGeneration++;
    if (isFileSource) {
      return _initPlayerIfNeeded(autoFullScreenFlag, force: fromReset);
    }
    if (fromReset && _networkSource != null) {
      _rememberPlaybackState();
      defaultST = null;
    }
    final identity = (bvid, cid.value, epId, seasonId);
    final contentKey = isUgc
        ? 'ugc:$bvid:${cid.value}'
        : 'pgc:${seasonId ?? 0}:${epId ?? 0}:${cid.value}';
    final configuration = plPlayerController.capturePlaybackConfiguration(
      live: false,
      source: _networkSource,
      mediaVolume: volume,
    );
    final accountOwner = AccountScope.captureVideo();
    final account = accountOwner.account;
    final mediaQuery = _captureVideoQuery(account);
    _videoQueryCancel?.cancel();
    _videoQueryCancel = mediaQuery;
    final fetch = mediaQuery.fetch;
    final ownsPlayback = playbackOwner.guard();
    bool ownsSource() =>
        !isClosed &&
        ownsPlayback() &&
        !mediaQuery.isCancelled &&
        identical(_videoQueryCancel, mediaQuery) &&
        accountOwner.isCurrent &&
        identity == (bvid, cid.value, epId, seasonId);
    final start =
        startPolicy ??
        (plPlayerController.currentPlaybackContentKey == contentKey
            ? PlaybackStartPolicy.preserve
            : _autoPlay.value
            ? PlaybackStartPolicy.play
            : PlaybackStartPolicy.pause);
    PlaybackQuery? acceptedQuery;
    int? deferredQuality;
    final result = await submitPlaybackQuery(
      (query) {
        acceptedQuery = query;
        query.registerCancel(mediaQuery.cancel);
        return _queryVideoUrl(
          fromReset,
          fetch,
          configuration,
          query,
          ownsSource,
          (quality) => deferredQuality = quality,
        );
      },
      start: start,
      shouldLoad: () => _shouldInitializePlayer(force: fromReset),
    );
    final query = acceptedQuery;
    bool valid() => query?.isCurrent == true && ownsSource();
    if (!valid()) return;
    if (result.outcome == LoadOutcome.ready) {
      videoState.value = true;
      plPlayerController.onPlaybackQueryReady(
        autoFullScreenFlag: autoFullScreenFlag && _autoPlay.value,
      );
      unawaited(setSubtitle(vttSubtitlesIndex.value));
      afterPlaybackReady(valid);
      defaultST = null;
    }
    if (deferredQuality case final quality?
        when result.outcome == LoadOutcome.ready ||
            result.outcome == LoadOutcome.noMedia) {
      final sourceData = data;
      bool stillOwnsData() => ownsSource() && identical(data, sourceData);
      unawaited(() async {
        if (await _supplementVideoQualities(
              sourceData,
              quality,
              fetch,
              stillOwnsData,
            ) &&
            stillOwnsData()) {
          availableVideoQualities.value =
              sourceData.dash!.video!.availableVideoQualities;
        }
      }());
    }
  }

  Future<PlaybackPlan?> _queryVideoUrl(
    bool fromReset,
    Future<LoadingState<PlayUrlModel>> Function(int) fetch,
    PlaybackConfiguration configuration,
    PlaybackQuery query,
    bool Function() ownsSource,
    void Function(int) deferSupplement,
  ) async {
    bool isCurrent() => query.isCurrent && ownsSource();
    if (plPlayerController.enableSponsorBlock && isBlock && !fromReset) {
      querySponsorBlock(bvid: bvid, cid: cid.value, isCurrent: isCurrent);
    }
    if (!isCurrent()) return null;
    final network = plPlayerController.cacheVideoQa == null
        ? ConnectivityUtils.isWiFi
        : null;
    final result = await fetch(VideoQuality.hdrVivid.code);
    if (network != null) {
      final isWiFi = await network;
      if (!isCurrent()) return null;
      plPlayerController
        ..cacheVideoQa = VideoPreferences.qualityCode(wifi: isWiFi)
        ..cacheAudioQa = AudioPreferences.qualityCode(wifi: isWiFi);
      preferCodecs = VideoPreferences.codecs(wifi: isWiFi);
    }

    if (!isCurrent()) return null;

    if (result case Success(:final response)) {
      final targetQuality = response.targetVideoQuality(
        plPlayerController.cacheVideoQa!,
      );
      if (response.missingVideoQualityBelowHighest case final quality?) {
        if (response.findAvailableVideoQuality(targetQuality) !=
                targetQuality &&
            quality >= targetQuality) {
          await _supplementVideoQualities(response, quality, fetch, isCurrent);
        } else {
          deferSupplement(quality);
        }
      }
      if (!isCurrent()) return null;
      data = response;
      availableVideoQualities.value =
          data.dash?.video?.availableVideoQualities ?? const {};

      languages.value = data.language?.items;
      currLang.value = data.curLanguage;

      volume = data.volume;

      if (!fromReset) {
        final progress = args.remove('progress');
        if (progress != null) {
          defaultST = Duration(milliseconds: progress);
        } else {
          defaultST = Duration(milliseconds: data.lastPlayTime);
        }
      }

      if (!isUgc && !fromReset && plPlayerController.enablePgcSkip) {
        if (data.clipInfoList case final clipInfoList?) {
          resetBlock();
          handleSBData(clipInfoList);
        }
      }

      if (data.acceptDesc?.contains('试看') == true) {
        SmartDialog.showToast(
          '该视频为专属视频，仅提供试看',
          displayTime: const Duration(seconds: 3),
        );
      }
      if (data.dash == null) {
        if (data.durl?.isNotEmpty == true) {
          _applyPlaybackSource(
            VideoPlaybackSource.resolve(
              data,
              videoQuality: data.quality!,
              audioQuality: plPlayerController.cacheAudioQa,
              preferredCodecs: preferCodecs,
            ),
          );
          _setVideoHeight();
        } else {
          SmartDialog.showToast('视频资源不存在');
          _autoPlay.value = false;
          videoState.value = false;
          if (plPlayerController.isFullScreen.value) {
            plPlayerController.triggerFullScreen(status: false);
          }
          return null;
        }
      } else {
        _applyPlaybackSource(
          VideoPlaybackSource.resolve(
            data,
            videoQuality: data.findAvailableVideoQuality(targetQuality),
            audioQuality: plPlayerController.cacheAudioQa,
            preferredCodecs: preferCodecs,
          ),
        );
        _setVideoHeight();
      }
      if (!isCurrent() || _networkSource == null) {
        return null;
      }
      final plan = _buildPlaybackPlan(_networkSource!, configuration);
      plPlayerController.preparePlaybackPlan(
        owner: playbackOwner,
        plan: plan,
        live: false,
        isVertical: isVertical.value,
        aid: aid,
        bvid: bvid,
        cid: cid.value,
        epid: isUgc ? null : epId,
        seasonId: isUgc ? null : seasonId,
        pgcType: isUgc ? null : pgcType,
        videoType: videoType,
      );
      _playbackPlan = plan;
      return plan;
    } else {
      _autoPlay.value = false;
      videoState.value = false;
      if (plPlayerController.isFullScreen.value) {
        plPlayerController.triggerFullScreen(status: false);
      }
      result.toast();
      return null;
    }
  }

  late final List<PostSegmentModel> postList = <PostSegmentModel>[];
  void onBlock(BuildContext context) {
    if (postList.isEmpty) {
      postList.add(
        PostSegmentModel(
          segment: Pair(
            first: 0,
            second: plPlayerController.positionInMilliseconds / 1000,
          ),
          category: SegmentType.sponsor,
          actionType: ActionType.skip,
        ),
      );
    }
    if (plPlayerController.isFullScreen.value || showVideoSheet) {
      final child = PostPanel(
        enableSlide: false,
        videoDetailController: this,
        plPlayerController: plPlayerController,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: plPlayerController.darkVideoPage
            ? Theme(data: ThemeUtils.darkTheme, child: child)
            : child,
      );
    } else {
      childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => PostPanel(
          videoDetailController: this,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }

  final _subtitles = ValueNotifier<List<Subtitle>>(const []);
  ValueListenable<List<Subtitle>> get subtitleTracks => _subtitles;
  List<Subtitle> get subtitles => _subtitles.value;
  final subtitleSources = SubtitleSources();
  Map<int, SubtitleSource> get vttSubtitles => subtitleSources.snapshot;
  final vttSubtitlesIndex = ValueNotifier(-1);
  bool? inheritedSubtitleEnabled;
  final showVP = ValueNotifier(true);
  final _viewPoints = ValueNotifier<List<ViewPointSegment>>(const []);
  ValueListenable<List<ViewPointSegment>> get viewPoints => _viewPoints;
  List<ViewPointSegment> get viewPointList => _viewPoints.value;
  void setViewPointsVisible(bool value) => showVP.value = value;
  void toggleViewPoints() => setViewPointsVisible(!showVP.value);

  // 设定字幕轨道
  int _subtitleGeneration = 0;
  bool Function() captureSubtitleMedia() => _mediaGuard();

  Future<void> addLocalSubtitle(
    String path,
    String name, {
    required bool Function() isCurrent,
  }) async {
    final source = await SubtitleSources.importFile(path, name);
    if (!isCurrent()) return;
    final index = subtitles.length;
    subtitleSources.remember(index, source);
    _subtitles.value = List.unmodifiable([
      ...subtitles,
      Subtitle(lan: '', lanDoc: name.split('.').first),
    ]);
    await setSubtitle(index + 1);
  }

  Future<void> setSubtitle(int index) async {
    final generation = ++_subtitleGeneration;
    final currentMedia = _mediaGuard();
    final owner = plPlayerController.activePlaybackOwner;
    if (owner == null || !identical(owner, playbackOwner)) return;
    bool valid() => currentMedia() && generation == _subtitleGeneration;
    if (!valid()) return;
    if (index <= 0) {
      final result = await applyPlaybackSubtitleTrack(
        const PlaybackSubtitleTrack.no(),
      );
      if (valid() &&
          (result.outcome == CommandOutcome.applied ||
              result.outcome == CommandOutcome.accepted)) {
        vttSubtitlesIndex.value = index;
      }
      return;
    }
    if (index > subtitles.length) {
      SmartDialog.showToast('字幕列表已更新，请重新选择');
      return;
    }
    final item = subtitles[index - 1];
    final source = await subtitleSources.forPlayback(
      index - 1,
      item.subtitleUrl ?? '',
      isCurrent: valid,
    );
    if (!valid() || source == null) return;
    if (source is! Success<SubtitleSource>) {
      unawaited(source.toast());
      return;
    }
    final subtitle = source.response;
    final result = await applyPlaybackSubtitleTrack(
      PlaybackSubtitleTrack.external(
        subtitle.isData ? 'memory://${subtitle.id}' : subtitle.id,
        title: item.lanDoc,
        language: item.lan,
      ),
    );
    if (valid() &&
        (result.outcome == CommandOutcome.applied ||
            result.outcome == CommandOutcome.accepted)) {
      vttSubtitlesIndex.value = index;
    }
  }

  // interactive video
  int? graphVersion;
  EdgeInfoData? steinEdgeInfo;
  final showSteinEdgeInfo = ValueNotifier(false);

  final _metadata = VideoMetadata();

  Future<void> getSteinEdgeInfo([int? edgeId]) async {
    final currentMedia = _mediaGuard();
    if (!currentMedia()) return;
    final version = graphVersion;
    steinEdgeInfo = null;
    final edge = await _metadata.interactiveEdge(
      bvid: bvid,
      graphVersion: version,
      edgeId: edgeId,
      isCurrent: () => currentMedia() && version == graphVersion,
    );
    if (edge != null && currentMedia() && version == graphVersion) {
      steinEdgeInfo = edge;
    }
  }

  late bool continuePlayingPart = VideoPreferences.resumeLastPart;

  Future<void> _queryPlayInfo({required bool Function() isCurrent}) async {
    if (!isCurrent()) return;
    final owner = AccountScope.capture();
    bool valid() => isCurrent() && owner.isCurrent;
    final res = await VideoMediaQuery.metadata(
      owner: owner,
      bvid: bvid,
      cid: cid.value,
      seasonId: seasonId,
      epId: epId,
    );
    if (!valid() || res == null) return;
    subtitleSources.clear();
    vttSubtitlesIndex.value = 0;
    if (plPlayerController.showViewPoints) {
      _viewPoints.value = const [];
    }
    if (res case Success(:final response)) {
      // interactive video
      final introCtr = _ugcIntro;
      if (isUgc && graphVersion == null) {
        try {
          if (introCtr?.videoDetail.value.rights?.isSteinGate == 1) {
            graphVersion = response.interaction?.graphVersion;
            getSteinEdgeInfo();
          }
        } catch (e, stackTrace) {
          logger.w('handle stein failed', error: e, stackTrace: stackTrace);
        }
      }

      if (isUgc && continuePlayingPart) {
        continuePlayingPart = false;
        final lastCid = response.lastPlayCid;
        if (lastCid != null && lastCid != 0 && lastCid != cid.value) {
          try {
            final pages = introCtr?.videoDetail.value.pages;
            if (pages != null && pages.length > 1) {
              final index = pages.indexWhere((item) => item.cid == lastCid);
              if (index != -1) {
                onAddItem(index);
              }
            }
          } catch (_) {}
        }
      }

      if (!valid()) return;
      if (plPlayerController.showViewPoints &&
          response.viewPoints?.firstOrNull?.type == 2) {
        try {
          _viewPoints.value = List.unmodifiable(
            response.viewPoints!.map((item) {
              final end = (item.to! / (data.timeLength! / 1000)).clamp(
                0.0,
                1.0,
              );
              return ViewPointSegment(
                end: end,
                title: item.content,
                url: item.imgUrl,
                from: item.from,
                to: item.to,
              );
            }),
          );
        } catch (_) {}
      }

      if (response.subtitle?.subtitles case final sub? when (sub.isNotEmpty)) {
        _setSubtitle(sub, isCurrent: valid);
      } else if (!owner.account.isLogin) {
        final res = await SubtitleSources.publicTracks(aid, cid.value);
        if (!valid()) return;
        if (res case Success(:final response)) {
          if (response.isNotEmpty) _setSubtitle(response, isCurrent: valid);
        } else {
          res.toast();
        }
      }
    }
  }

  Future<void> _setSubtitle(
    List<Subtitle> sub, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    _subtitles.value = List.unmodifiable(sub);
    final selectionGeneration = _subtitleGeneration;
    final preferredIndex = switch (VideoPreferences.subtitle) {
      .off => 0,
      .on => 1,
      .withoutAi => sub.first.lan.startsWith('ai') ? 0 : 1,
      .auto =>
        !sub.first.lan.startsWith('ai') ||
                (PlatformUtils.isMobile &&
                    (await FlutterVolumeController.getVolume() ?? 0.0) <= 0.0)
            ? 1
            : 0,
    };
    if (!isCurrent() || selectionGeneration != _subtitleGeneration) return;
    final inheritedState = inheritedSubtitleEnabled;
    inheritedSubtitleEnabled = null;
    final idx = inheritedState == null
        ? preferredIndex
        : inheritedState
        ? 1
        : 0;
    await setSubtitle(idx);
  }

  void updateMediaListHistory(int aid) => _playlist?.recordProgress(aid);

  void reportVideo() {
    if (isClosed) return;
    if (AccountScope.signedIn) {
      PageUtils.reportVideo(aid);
    } else {
      SmartDialog.showToast('账号未登录');
    }
  }

  void makeHeartBeat() {
    if (plPlayerController.enableHeart &&
        !plPlayerController.playerStatus.isCompleted &&
        playedTime != null) {
      try {
        plPlayerController.makeHeartBeat(
          data.timeLength != null
              ? (data.timeLength! - playedTime!.inMilliseconds).abs() <= 1000
                    ? -1
                    : playedTime!.inSeconds
              : playedTime!.inSeconds,
          type: HeartBeatType.completed,
          isManual: true,
          aid: aid,
          bvid: bvid,
          cid: cid.value,
          epid: isUgc ? null : epId,
          seasonId: isUgc ? null : seasonId,
          pgcType: isUgc ? null : pgcType,
          videoType: videoType,
        );
      } catch (_) {}
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _playlist?.close();
    _videoQueryCancel?.cancel();
    _subtitleGeneration++;
    _shutdownBinding?.dispose();
    plPlayerController.closePlaybackOwner(playbackOwner);
    if (isFileSource) {
      cacheLocalProgress();
    }
    introScrollCtr?.dispose();
    introScrollCtr = null;
    tabCtr.dispose();
    _scrollCtr?.dispose();
    animController
      ?..removeListener(_animListener)
      ..dispose();
    subtitleSources.clear();
    disposeBlock();
    for (final state in <ChangeNotifier>[
      cover,
      cid,
      _episodeOrderRevision,
      seasonIndex,
      videoState,
      currentVideoQa,
      availableVideoQualities,
      _autoPlay,
      isVertical,
      scrollRatio,
      languages,
      currLang,
      _subtitles,
      vttSubtitlesIndex,
      showVP,
      _viewPoints,
      showSteinEdgeInfo,
      dmTrend,
      showDmTrendChart,
      videoLabel,
    ]) {
      state.dispose();
    }
  }

  void onReset({bool isStein = false}) {
    _videoQueryCancel?.cancel();
    _subtitleGeneration++;
    playbackOwner.invalidateRequests();
    if (isFileSource) {
      cacheLocalProgress();
    }

    playedTime = null;
    defaultST = null;
    _networkSource = null;
    currentAudioQa = null;

    // danmaku
    savedDanmaku = null;

    // subtitle
    _subtitles.value = const [];
    vttSubtitlesIndex.value = -1;
    subtitleSources.clear();

    if (!isFileSource) {
      // language
      languages.value = null;
      currLang.value = null;

      // dm trend
      if (plPlayerController.showDmChart) {
        dmTrend.value = null;
      }

      // view point
      if (plPlayerController.showViewPoints) {
        _viewPoints.value = const [];
      }

      // sponsor block
      if (blockConfig.enableBlock) {
        resetBlock();
      }

      // interactive video
      if (!isStein) {
        graphVersion = null;
      }
      steinEdgeInfo = null;
      showSteinEdgeInfo.value = false;
    }
  }

  final dmTrend = ValueNotifier<LoadingState<List<double>>?>(null);
  final showDmTrendChart = ValueNotifier(true);

  Future<void> _getDmTrend({required bool Function() isCurrent}) async {
    if (!isCurrent()) return;
    dmTrend.value = LoadingState.loading();
    final result = await _metadata.danmakuTrend(
      aid: aid,
      bvid: bvid,
      cid: cid.value,
    );
    if (isCurrent()) dmTrend.value = result;
  }

  void showNoteList(BuildContext context) {
    final title = _ugcIntro?.videoDetail.value.title;
    if (plPlayerController.isFullScreen.value || showVideoSheet) {
      final child = NoteListPage(
        oid: aid,
        enableSlide: false,
        isStein: graphVersion != null,
        title: title,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: plPlayerController.darkVideoPage
            ? Theme(data: ThemeUtils.darkTheme, child: child)
            : child,
      );
    } else {
      childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => NoteListPage(
          oid: aid,
          isStein: graphVersion != null,
          title: title,
        ),
      );
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  bool onSkipSegment() {
    try {
      if (plPlayerController.enableBlock) {
        if (listData.lastOrNull case final SegmentModel item) {
          onSkip(item, isSeek: false);
          onRemoveItem(listData.indexOf(item), item);
          return true;
        }
      }
    } catch (e, s) {
      reportError(e, s);
    }
    return false;
  }

  void toAudioPage() {
    int? id;
    int? extraId;
    var from = AudioPlaylistSource.archive;
    if (isPlayAll) {
      id = args['mediaId'];
      extraId = sourceType.extraId;
      from = sourceType.playlistSource!;
    } else if (isUgc) {
      id = _ugcIntro?.videoDetail.value.ugcSeason?.id;
      if (id != null) {
        extraId = 8;
        from = AudioPlaylistSource.mediaList;
      }
    }
    final video = bvid;
    final part = cid.value;
    AudioPage.toAudioPage(
      itemType: 1,
      id: id,
      oid: aid,
      subId: [cid.value],
      from: from,
      initialVolume: _autoPlay.value ? volume : null,
      onPosition: _autoPlay.value
          ? (position) {
              if (!isClosed && bvid == video && cid.value == part) {
                playedTime = position;
              }
            }
          : null,
      start: playedTime,
      audioUrl: audioUrl,
      extraId: extraId,
    );
  }

  Future<void> onDownload(BuildContext context) async {
    VideoDetailData? videoDetail;
    List<ugc.BaseEpisodeItem>? episodes;
    UgcIntroController? ugcIntroController;
    PgcInfoModel? pgcItem;
    if (isUgc) {
      try {
        ugcIntroController = _ugcIntro;
        videoDetail = ugcIntroController?.videoDetail.value;
        if (videoDetail?.ugcSeason?.sections case final sections?) {
          episodes = <ugc.BaseEpisodeItem>[];
          for (final i in sections) {
            if (i.episodes case final e?) {
              episodes.addAll(e);
            }
          }
        } else {
          episodes = videoDetail?.pages;
        }
      } catch (e, s) {
        logger.w('download ugc failed', error: e, stackTrace: s);
      }
    } else {
      try {
        pgcItem = _pgcIntro?.pgcItem;
        episodes = pgcItem?.episodes;
      } catch (e, s) {
        logger.w('download pgc failed', error: e, stackTrace: s);
      }
    }
    if (episodes != null && episodes.isNotEmpty) {
      final downloadService = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(downloadServiceProvider);
      final initialization = await downloadService.waitForInitialization;
      if (!context.mounted) {
        return;
      }
      if (!initialization.isSuccess) {
        initialization.toast();
        return;
      }
      final Set<int> cidSet = downloadService.downloadList
          .followedBy(downloadService.waitDownloadQueue)
          .map((e) => e.cid)
          .toSet();
      final index = episodes.indexWhere(
        (e) => e.cid == (seasonCid ?? cid.value),
      );

      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxWidth: min(640, context.mediaQueryShortestSide),
        ),
        builder: (context) {
          final maxChildSize =
              PlatformUtils.isMobile && !context.mediaQuerySize.isPortrait
              ? 1.0
              : 0.7;
          return DraggableScrollableSheet(
            snap: true,
            expand: false,
            minChildSize: 0,
            snapSizes: [maxChildSize],
            maxChildSize: maxChildSize,
            initialChildSize: maxChildSize,
            builder: (context, scrollController) => DownloadPanel(
              index: index,
              videoDetail: videoDetail,
              pgcItem: pgcItem,
              episodes: episodes!,
              scrollController: scrollController,
              videoDetailController: this,
              ugcIntroController: isUgc ? ugcIntroController : null,
              cidSet: cidSet,
            ),
          );
        },
      );
    }
  }

  bool _casting = false;

  Future<void> onCast() async {
    if (_casting || isClosed) return;
    _casting = true;
    final request = NavigationRequest();
    final requestCid = cid.value;
    final requestBvid = bvid;
    final requestAid = aid;
    final requestEpId = epId;
    final accountOwner = AccountScope.captureVideo();
    final account = accountOwner.account;
    bool current() =>
        !isClosed &&
        request.isCurrent &&
        cid.value == requestCid &&
        bvid == requestBvid &&
        aid == requestAid &&
        epId == requestEpId &&
        accountOwner.isCurrent;
    try {
      request.showLoading('投屏地址获取中');
      final res = await loadCastUrl(
        account: account,
        cid: requestCid,
        aid: requestAid,
        episodeId: requestEpId,
        quality: currentVideoQa.value?.code,
      );
      if (!current()) return;
      if (res case Success(response: final url)) {
        if (url == null) {
          SmartDialog.showToast('不支持投屏');
          return;
        }
        final title = isUgc
            ? _ugcIntro?.videoDetail.value.title
            : _pgcIntro?.videoDetail.value.title;
        Get.toNamed('/dlna', parameters: {'url': url, 'title': ?title});
      } else {
        res.toast();
      }
    } catch (error, stackTrace) {
      logger.w('获取投屏地址失败', error: error.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('投屏地址获取失败，请重试');
    } finally {
      await request.close();
      _casting = false;
    }
  }
}
