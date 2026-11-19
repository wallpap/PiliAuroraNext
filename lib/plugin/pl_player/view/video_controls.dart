import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/disabled_icon.dart';
import 'package:pili_aurora_next/common/widgets/player_bar.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/super_resolution_type.dart';
import 'package:pili_aurora_next/models/common/video/video_quality.dart';
import 'package:pili_aurora_next/models/video/play/url.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/episode.dart'
    as ugc;
import 'package:pili_aurora_next/models/remote/video/video_detail/ugc_season.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/pgc/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/bottom_control_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/video_fit_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/super_resolution_policy.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/common_btn.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/desktop_volume_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/connectivity_utils.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pili_aurora_next/plugin/pl_player/view/video_time.dart';

typedef ShowPlayerEpisodes = void Function([
  int?,
  UgcSeason?,
  List<ugc.BaseEpisodeItem>?,
  String?,
  int?,
  int?,
]);

class VideoControls extends StatefulWidget {
  const VideoControls({
    super.key,
    required this.plPlayerController,
    required this.videoDetailController,
    required this.introController,
    required this.maxWidth,
    required this.isLandscape,
    required this.isFullScreen,
    this.showEpisodes,
    this.showViewPoints,
  });

  final PlPlayerController plPlayerController;
  final VideoDetailController videoDetailController;
  final CommonIntroController introController;
  final double maxWidth;
  final bool isLandscape;
  final bool isFullScreen;
  final ShowPlayerEpisodes? showEpisodes;
  final VoidCallback? showViewPoints;

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  PlPlayerController get plPlayerController => widget.plPlayerController;
  VideoDetailController get videoDetailController =>
      widget.videoDetailController;
  CommonIntroController get introController => widget.introController;

  @override
  Widget build(BuildContext context) {
    final videoDetail = introController.videoDetail.value;
    final isSeason = videoDetail.ugcSeason != null;
    final isPart = videoDetail.pages != null && videoDetail.pages!.length > 1;
    final isPgc = !videoDetailController.isUgc;
    final isPlayAll = videoDetailController.isPlayAll;
    final anySeason = isSeason || isPart || isPgc || isPlayAll;
    final isFullScreen = widget.isFullScreen;
    final double widgetWidth = widget.isLandscape && isFullScreen ? 42 : 35;

    Widget progressWidget(
      BottomControlType bottomControl,
    ) => switch (bottomControl) {
      BottomControlType.volume => DesktopVolumeControl(
        volume: plPlayerController.volume,
        muted: plPlayerController.muted,
        maxVolume: plPlayerController.maxVolume,
        onChanged: (value) =>
            plPlayerController.setVolume(value, showIndicator: false),
        onMuteChanged: plPlayerController.setMutedFromControls,
        onOpened: () => plPlayerController.setControlsMenuOpen(true),
        onClosed: () => plPlayerController.setControlsMenuOpen(false),
      ),

      /// 播放暂停
      BottomControlType.playOrPause => PlayOrPauseButton(
        plPlayerController: plPlayerController,
      ),

      /// 上一集
      BottomControlType.pre => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: '上一集',
        icon: const Icon(
          Icons.skip_previous,
          size: 22,
          color: Colors.white,
        ),
        onTap: () {
          if (!introController.prevPlay()) {
            SmartDialog.showToast('已经是第一集了');
          }
        },
      ),

      /// 下一集
      BottomControlType.next => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: '下一集',
        icon: const Icon(
          Icons.skip_next,
          size: 22,
          color: Colors.white,
        ),
        onTap: () {
          if (!introController.nextPlay()) {
            SmartDialog.showToast('已经是最后一集了');
          }
        },
      ),

      /// 时间进度
      BottomControlType.time => Obx(
        () => VideoTime(
          position: DurationUtils.formatDuration(
            plPlayerController.position.value,
          ),
          duration: DurationUtils.formatDuration(
            plPlayerController.duration.value,
          ),
        ),
      ),

      /// 高能进度条
      BottomControlType.dmChart => ListenableBuilder(
        listenable: Listenable.merge([
          videoDetailController.dmTrend,
          videoDetailController.showDmTrendChart,
        ]),
        builder: (context, child) {
          final list = videoDetailController.dmTrend.value?.dataOrNull;
          if (list != null && list.isNotEmpty) {
            final show = videoDetailController.showDmTrendChart.value;
            return ComBtn(
              width: widgetWidth,
              height: 30,
              tooltip: '高能进度条',
              icon: DisabledIcon(
                disable: !show,
                child: const Icon(
                  Icons.show_chart,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              onTap: () => videoDetailController.showDmTrendChart.value = !show,
            );
          }
          return const SizedBox.shrink();
        },
      ),

      /// 超分辨率
      BottomControlType.superResolution => Obx(
        () {
          final type = plPlayerController.superResolutionType.value;
          final availability = plPlayerController.superResolutionAvailability;
          final canEnable = availability == SuperResolutionEligibility.allowed;
          final hint = switch (availability) {
            SuperResolutionEligibility.allowed => '超分辨率',
            SuperResolutionEligibility.resolutionTooHigh => '视频分辨率过高，无法开启超分',
            SuperResolutionEligibility.unknownSize => '等待视频和屏幕尺寸，暂无法开启超分',
          };
          return GestureDetector(
            onTap: canEnable ? null : () => SmartDialog.showToast(hint),
            child: PopupMenuButton<SuperResolutionType>(
              enabled: canEnable,
              tooltip: hint,
              requestFocus: false,
              initialValue: type,
              itemBuilder: (context) {
                return SuperResolutionType.values
                    .map(
                      (option) => AppPopupMenuItem<SuperResolutionType>(
                        height: 35,
                        value: option,
                        enabled:
                            option == SuperResolutionType.disable || canEnable,
                        selected: option == type,
                        onTap: () => plPlayerController.setShader(option),
                        child: Text(
                          option.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  type.label,
                  style: TextStyle(
                    color: canEnable ? Colors.white : Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),

      /// 分段信息
      BottomControlType.viewPoints => ListenableBuilder(
        listenable: Listenable.merge([
          videoDetailController.viewPoints,
          videoDetailController.showVP,
        ]),
        builder: (context, child) {
          if (videoDetailController.viewPointList.isNotEmpty) {
            return ComBtn(
              width: widgetWidth,
              height: 30,
              tooltip: '分段信息',
              icon: DisabledIcon(
                disable: !videoDetailController.showVP.value,
                child: const Icon(
                  CustomIcons.view_headline_rotate_90,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              onTap: widget.showViewPoints,
              onLongPress: () {
                Feedback.forLongPress(context);
                videoDetailController.toggleViewPoints();
              },
              onSecondaryTap: PlatformUtils.isMobile
                  ? null
                  : videoDetailController.toggleViewPoints,
            );
          }
          return const SizedBox.shrink();
        },
      ),

      /// 选集
      BottomControlType.episode => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: '选集',
        icon: const Icon(
          Icons.list,
          size: 22,
          color: Colors.white,
        ),
        onTap: () {
          if (videoDetailController.isFileSource) {
            return;
          }
          // part -> playAll -> season(pgc)
          if (isPlayAll && !isPart) {
            widget.showEpisodes?.call();
            return;
          }
          int? index;
          int currentCid = plPlayerController.cid!;
          String bvid = plPlayerController.bvid;
          List<ugc.BaseEpisodeItem> episodes = [];
          if (isSeason) {
            final sections = videoDetail.ugcSeason!.sections!;
            for (int i = 0; i < sections.length; i++) {
              final episodesList = sections[i].episodes!;
              for (final item in episodesList) {
                if (item.cid == currentCid) {
                  index = i;
                  episodes = episodesList;
                  break;
                }
              }
            }
          } else if (isPart) {
            episodes = videoDetail.pages!;
          } else if (isPgc) {
            episodes =
                (introController as PgcIntroController).pgcItem.episodes!;
          }
          widget.showEpisodes?.call(
            index,
            isSeason ? videoDetail.ugcSeason! : null,
            isSeason ? null : episodes,
            bvid,
            IdUtils.bv2av(bvid),
            isSeason && isPart
                ? videoDetailController.seasonCid ?? currentCid
                : currentCid,
          );
        },
      ),

      /// 画面比例
      BottomControlType.fit => Obx(
        () {
          final fit = plPlayerController.videoFit.value;
          return PopupMenuButton<VideoFitType>(
            tooltip: '画面比例',
            requestFocus: false,
            initialValue: fit,
            itemBuilder: (context) {
              return VideoFitType.values
                  .map(
                    (boxFit) => AppPopupMenuItem<VideoFitType>(
                      height: 35,
                      value: boxFit,
                      selected: boxFit == fit,
                      onTap: () => plPlayerController.toggleVideoFit(boxFit),
                      child: Text(
                        boxFit.desc,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                fit.desc,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          );
        },
      ),

      BottomControlType.aiTranslate => ListenableBuilder(
        listenable: Listenable.merge([
          videoDetailController.languages,
          videoDetailController.currLang,
        ]),
        builder: (context, child) {
          final list = videoDetailController.languages.value;
          if (list != null && list.isNotEmpty) {
            return PopupMenuButton<String>(
              tooltip: '翻译',
              requestFocus: false,
              initialValue: videoDetailController.currLang.value,
              onSelected: videoDetailController.setLanguage,
              itemBuilder: (context) => [
                AppPopupMenuItem<String>(
                  height: 35,
                  value: '',
                  selected:
                      (videoDetailController.currLang.value ?? '').isEmpty,
                  child: const Text(
                    "关闭翻译",
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                ...list.map(
                  (e) => AppPopupMenuItem<String>(
                    height: 35,
                    value: e.lang,
                    selected: videoDetailController.currLang.value == e.lang,
                    child: Text(
                      e.title!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              child: SizedBox(
                width: widgetWidth,
                height: 30,
                child: const Icon(
                  Icons.translate,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),

      /// 字幕
      BottomControlType.subtitle => ListenableBuilder(
        listenable: Listenable.merge([
          videoDetailController.subtitleTracks,
          videoDetailController.vttSubtitlesIndex,
        ]),
        builder: (context, child) {
          if (videoDetailController.subtitles.isNotEmpty) {
            final val = videoDetailController.vttSubtitlesIndex.value;
            return PopupMenuButton<int>(
              tooltip: '字幕',
              requestFocus: false,
              initialValue: val,
              itemBuilder: (context) {
                return [
                  AppPopupMenuItem<int>(
                    value: 0,
                    height: 35,
                    selected: val == 0,
                    onTap: () => videoDetailController.setSubtitle(0),
                    child: const Text(
                      "关闭字幕",
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  ...videoDetailController.subtitles.mapIndexed((i, e) {
                    return AppPopupMenuItem<int>(
                      value: i + 1,
                      height: 35,
                      selected: val == i + 1,
                      onTap: () => videoDetailController.setSubtitle(i + 1),
                      child: Text(
                        e.lanDoc ?? e.lan,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }),
                ];
              },
              child: SizedBox(
                width: widgetWidth,
                height: 30,
                child: val == 0
                    ? const Icon(
                        Icons.closed_caption_off_outlined,
                        size: 22,
                        color: Colors.white,
                      )
                    : const Icon(
                        Icons.closed_caption_off_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),

      /// 播放速度
      BottomControlType.speed => Obx(
        () => PopupMenuButton<double>(
          tooltip: '倍速',
          requestFocus: false,
          initialValue: plPlayerController.playbackSpeed,
          itemBuilder: (context) {
            return plPlayerController.speedList
                .map(
                  (double speed) => AppPopupMenuItem<double>(
                    height: 35,
                    value: speed,
                    selected: speed == plPlayerController.playbackSpeed,
                    onTap: () => plPlayerController.setPlaybackSpeed(speed),
                    child: Text(
                      "${speed}X",
                      style: const TextStyle(fontSize: 13),
                      semanticsLabel: "$speed倍速",
                    ),
                  ),
                )
                .toList();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "${plPlayerController.playbackSpeed}X",
              style: const TextStyle(color: Colors.white, fontSize: 13),
              semanticsLabel: "${plPlayerController.playbackSpeed}倍速",
            ),
          ),
        ),
      ),

      BottomControlType.qa => ListenableBuilder(
        listenable: Listenable.merge([
          videoDetailController.currentVideoQa,
          videoDetailController.availableVideoQualities,
        ]),
        builder: (context, child) {
          final VideoQuality? currentVideoQa =
              videoDetailController.currentVideoQa.value;
          if (currentVideoQa == null) {
            return const SizedBox.shrink();
          }
          final PlayUrlModel videoInfo = videoDetailController.data;
          if (videoInfo.dash == null) {
            return const SizedBox.shrink();
          }
          final videoFormat = videoInfo.supportFormats ?? const <FormatItem>[];
          final tracks = videoInfo.dash?.video;
          if (tracks == null || tracks.isEmpty) return const SizedBox.shrink();
          final availableQa =
              videoDetailController.availableVideoQualities.value;
          return PopupMenuButton<int>(
            tooltip: '画质',
            requestFocus: false,
            initialValue: currentVideoQa.code,
            itemBuilder: (context) {
              return List.generate(
                videoFormat.length,
                (index) {
                  final item = videoFormat[index];
                  final enabled = availableQa.contains(item.quality);
                  return AppPopupMenuItem<int>(
                    enabled: enabled,
                    height: 35,
                    value: item.quality,
                    selected: currentVideoQa.code == item.quality,
                    onTap: () async {
                      final details = videoDetailController;
                      if (details.currentVideoQa.value?.code == item.quality &&
                          details.playbackSourceMatchesSelection &&
                          plPlayerController.currentPlaybackSnapshot.phase ==
                              PlaybackPhase.ready) {
                        return;
                      }
                      final int quality = item.quality!;
                      final newQa = VideoQuality.fromCode(quality);
                      if (!identical(details.data, videoInfo)) return;
                      final ownsPlayback = details.playbackOwner.guard();
                      final result = await details.updatePlayer(
                        videoQuality: newQa,
                      );
                      if (!mounted ||
                          !identical(widget.videoDetailController, details) ||
                          details.isClosed ||
                          !ownsPlayback() ||
                          !identical(details.data, videoInfo) ||
                          result.outcome != LoadOutcome.ready) {
                        return;
                      }

                      SmartDialog.showToast("画质已变为：${newQa.desc}");

                      if (!plPlayerController.tempPlayerConf) {
                        final network = await ConnectivityUtils.queryWiFi();
                        if (!mounted ||
                            !identical(widget.videoDetailController, details) ||
                            details.isClosed ||
                            !ownsPlayback() ||
                            !identical(details.data, videoInfo) ||
                            plPlayerController.tempPlayerConf ||
                            plPlayerController.cacheVideoQa != quality) {
                          return;
                        }
                        if (network is! Success<bool>) {
                          SmartDialog.showToast('画质已应用，网络类型未知，未保存默认值');
                          return;
                        }
                        try {
                          await GStorage.setting.put(
                            network.response
                                ? SettingBoxKey.defaultVideoQa
                                : SettingBoxKey.defaultVideoQaCellular,
                            quality,
                          );
                        } catch (error, stackTrace) {
                          logger.w(
                            '保存默认画质失败',
                            error: error.runtimeType,
                            stackTrace: stackTrace,
                          );
                          if (mounted && !videoDetailController.isClosed) {
                            SmartDialog.showToast('画质已应用，默认值保存失败，请重试');
                          }
                        }
                      }
                    },
                    child: Text(
                      item.newDesc ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                currentVideoQa.shortDesc,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          );
        },
      ),

      /// 全屏
      BottomControlType.fullscreen => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: isFullScreen ? '退出全屏' : '全屏',
        icon: isFullScreen
            ? const Icon(Icons.fullscreen_exit, size: 24, color: Colors.white)
            : const Icon(Icons.fullscreen, size: 24, color: Colors.white),
        onTap: () =>
            plPlayerController.triggerFullScreen(status: !isFullScreen),
        onSecondaryTap: () => plPlayerController.triggerFullScreen(
          status: !isFullScreen,
          inAppFullScreen: true,
        ),
      ),
    };

    final isNotFileSource = !plPlayerController.isFileSource;

    List<BottomControlType> userSpecifyItemLeft = [
      .playOrPause,
      .time,
      if (PlatformUtils.isDesktop) .volume,
      if (!isNotFileSource || anySeason) ...[.pre, .next],
    ];

    final flag =
        isFullScreen ||
        plPlayerController.isDesktopPip ||
        widget.maxWidth >= 500;
    final List<BottomControlType> userSpecifyItemRight = [
      if (isNotFileSource && plPlayerController.showDmChart) .dmChart,
      if (plPlayerController.isAnim) .superResolution,
      if (isNotFileSource && plPlayerController.showViewPoints) .viewPoints,
      if (isNotFileSource && anySeason) .episode,
      if (flag) .fit,
      if (isNotFileSource) .aiTranslate,
      .subtitle,
      .speed,
      if (isNotFileSource && flag) .qa,
      if (!plPlayerController.isDesktopPip) .fullscreen,
    ];
    return PlayerBar(
      children: [
        Row(
          mainAxisSize: .min,
          children: userSpecifyItemLeft.map(progressWidget).toList(),
        ),
        Row(
          mainAxisSize: .min,
          children: userSpecifyItemRight.map(progressWidget).toList(),
        ),
      ],
    );
  }
}
