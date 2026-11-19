import 'dart:async';

import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/constants.dart';
import 'package:pili_aurora_next/features/playback/application/video_details.dart';
import 'package:pili_aurora_next/features/playback/application/season_collection.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/common/video/video_type.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_info_model/episode.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_info_model/result.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/episode.dart'
    hide EpisodeItem;
import 'package:pili_aurora_next/models/remote/video/video_detail/stat_detail.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/utils/android/android_helper.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PgcIntroController extends CommonIntroController {
  int? seasonId;
  int? epId;

  late final String pgcType = pgcItem.type == 1 || pgcItem.type == 4
      ? '追番'
      : '追剧';

  late final bool isPgc;
  late final PgcInfoModel pgcItem;
  late List<EpisodeItem> _playbackEpisodes;

  @override
  (Object, int) get getFavRidType => (epId!, 24);

  @override
  StatDetail? getStat() => pgcItem.stat;

  int? get followSeasonId => pgcItem.seasonId ?? seasonId;
  SeasonCollection? _collection;
  SeasonCollection get collection => _collection ??= SeasonCollection(
    trackedSeason: () => followSeasonId,
    course: () => (season: seasonId, episode: epId),
    initialBookmark: () => switch (pgcItem.userStatus?.favored) {
      final value? => value == 1,
      _ => null,
    },
  );

  @override
  void open(VideoDetailController video, TickerProvider vsync) {
    final args = video.args;
    seasonId = args['seasonId'];
    epId = args['epId'];
    isPgc = args['videoType'] == VideoType.pgc;
    pgcItem = args['pgcItem'];
    _playbackEpisodes = pgcItem.episodes ?? <EpisodeItem>[];

    super.open(video, vsync);
    collection.observeAccount(pgc: isPgc);

    if (isPgc) {
      queryIsFollowed();
      if (isLogin && epId != null) queryPgcLikeCoinFav();
      queryVideoTags();
    }
  }

  void setPlaybackEpisodes(List<EpisodeItem> episodes) {
    if (episodes.isNotEmpty) {
      _playbackEpisodes = episodes;
    }
  }

  @override
  int? get interactionEpisode => epId;

  Future<void> queryPgcLikeCoinFav() async {
    final error = await interactions.refresh(pgc: true);
    if (!isClosed) error?.toast();
  }

  @override
  int get copyright => 1;

  // 分享视频
  @override
  void actionShareVideo(BuildContext context) {
    final epId = this.epId;
    if (epId == null) {
      SmartDialog.showToast('分集信息尚未加载，请重试');
      return;
    }
    final account = Accounts.main;
    final pgcTitle = pgcItem.title;
    final pgcCover = pgcItem.cover;
    final pgcType = pgcItem.type;
    final episodes = <EpisodeItem>[
      ...?pgcItem.episodes,
      for (final section in pgcItem.section ?? const []) ...?section.episodes,
    ];
    final item = episodes.firstWhereOrNull(
      (item) => (item.epId ?? item.id) == epId,
    );
    final showTitle = item?.showTitle;
    final messageTitle =
        item?.shareCopy ?? '$pgcTitle ${showTitle ?? item?.longTitle}';
    final shareUrl = item?.shareUrl;
    final shareCover = item?.cover;
    bool ownsAccount() =>
        context.mounted && !isClosed && identical(account, Accounts.main);

    String videoUrl =
        '${HttpString.baseUrl}/bangumi/play/ep$epId${videoDetailCtr.playedTimePos(false)}';
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          DialogOption(
            child: const Text('复制链接', style: TextStyle(fontSize: 14)),
            onPressed: () {
              Get.back();
              Utils.copyText(videoUrl);
            },
          ),
          DialogOption(
            child: const Text('其它app打开', style: TextStyle(fontSize: 14)),
            onPressed: () {
              Get.back();
              PiliAndroidHelper.openUrl(videoUrl);
            },
          ),
          if (PlatformUtils.isMobile)
            DialogOption(
              child: const Text('分享视频', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                ShareUtils.shareText(
                  '$pgcTitle${item != null ? ' $showTitle' : ''}'
                  ' - $videoUrl',
                );
              },
            ),
          if (isLogin)
            DialogOption(
              child: const Text('分享至动态', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                if (!ownsAccount()) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (context) => RepostPanel(
                    rid: epId,
                    /*
                    1：番剧 // 4097
                    2：电影 // 4098
                    3：纪录片 // 4101
                    4：国创 // 4100
                    5：电视剧 // 4099
                    6：漫画
                    7：综艺 // 4099
                  */
                    dynType: switch (pgcType) {
                      1 => 4097,
                      2 => 4098,
                      3 => 4101,
                      4 => 4100,
                      5 || 7 => 4099,
                      _ => -1,
                    },
                    pic: pgcCover,
                    title: '$pgcTitle${item != null ? '\n$showTitle' : ''}',
                    uname: '',
                  ),
                );
              },
            ),
          if (isLogin)
            DialogOption(
              child: const Text(
                '分享至消息',
                style: TextStyle(fontSize: 14),
              ),
              onPressed: () async {
                Get.back();
                if (!ownsAccount()) return;
                if (item == null) {
                  SmartDialog.showToast('分集信息不完整，请刷新后重试');
                  return;
                }
                try {
                  await PageUtils.pmShare(
                    context,
                    content: {
                      "id": epId.toString(),
                      "title": messageTitle,
                      "url": shareUrl,
                      "headline": messageTitle,
                      "source": 16,
                      "thumb": shareCover,
                      "source_desc": switch (pgcType) {
                        1 => '番剧',
                        2 => '电影',
                        3 => '纪录片',
                        4 => '国创',
                        5 => '电视剧',
                        6 => '漫画',
                        7 => '综艺',
                        _ => null,
                      },
                    },
                  );
                } catch (error, stack) {
                  logger.w(
                    '打开分集分享失败',
                    error: error.runtimeType,
                    stackTrace: stack,
                  );
                  if (ownsAccount()) SmartDialog.showToast('无法打开分享面板，请重试');
                }
              },
            ),
        ],
      ),
    );
  }

  // 修改分P或番剧分集
  int _episodeChange = 0;

  Future<bool> onChangeEpisode(BaseEpisodeItem episode) async {
    if (isClosed) return false;
    final version = ++_episodeChange;
    final account = Accounts.heartbeat;
    final mainAccount = Accounts.main;
    final source = (bvid, cid.value, epId);
    final videoSource = (videoDetailCtr.bvid, videoDetailCtr.cid.value);
    final ownsPlayback = videoDetailCtr.playbackOwner.guard();
    bool current() =>
        !isClosed &&
        version == _episodeChange &&
        identical(account, Accounts.heartbeat) &&
        identical(mainAccount, Accounts.main) &&
        source == (bvid, cid.value, epId) &&
        videoSource == (videoDetailCtr.bvid, videoDetailCtr.cid.value) &&
        ownsPlayback();
    try {
      if (!current()) return false;
      final int epId = episode.epId ?? episode.id!;
      final String bvid = episode.bvid ?? this.bvid;
      final int aid = episode.aid ?? IdUtils.bv2av(bvid);
      final String? cover = episode.cover;
      int? cid = episode.cid;
      if (cid == null || cid <= 0) {
        final result = await VideoDetails.resolvePart(account, bvid, aid);
        if (!current()) return false;
        if (result is Error) {
          result.toast();
          return false;
        }
        cid = result.dataOrNull?.cid;
      }
      if (!current()) return false;
      if (cid == null || cid <= 0) {
        SmartDialog.showToast('该分集暂无可播放内容');
        return false;
      }

      // 重新获取视频资源
      this.epId = epId;
      this.bvid = bvid;

      videoDetailCtr
        ..plPlayerController.pause()
        ..makeHeartBeat()
        ..onReset()
        ..epId = epId
        ..bvid = bvid
        ..aid = aid
        ..cid.value = cid
        ..queryVideoUrl();
      if (cover != null && cover.isNotEmpty) {
        videoDetailCtr.cover.value = cover;
      }

      videoDetailCtr.onReplyTargetChanged?.call();

      if (isPgc && isLogin) {
        queryPgcLikeCoinFav();
      }

      hasLater.value = videoDetailCtr.sourceType == SourceType.watchLater;
      this.cid.value = cid;
      queryOnlineTotal();
      queryVideoIntro(episode as EpisodeItem);
      return true;
    } catch (e, stackTrace) {
      logger.w('切换分集失败', error: e.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('切换分集失败，请重试');
      return false;
    }
  }

  Future<void> pgcAdd() =>
      showInteractionResult(collection.changeTracking(.add));
  Future<void> pgcDel() =>
      showInteractionResult(collection.changeTracking(.remove));
  Future<void> pgcUpdate(int status) => showInteractionResult(
    collection.changeTracking(.changeGroup, group: status),
  );

  @override
  bool prevPlay() {
    final episodes = _playbackEpisodes;
    if (episodes.isEmpty) return false;
    int currentIndex = episodes.indexWhere(
      (e) => e.cid == videoDetailCtr.cid.value,
    );
    int prevIndex = currentIndex - 1;
    PlayRepeat playRepeat = videoDetailCtr.plPlayerController.playRepeat;
    if (prevIndex < 0) {
      if (playRepeat == PlayRepeat.listCycle) {
        prevIndex = episodes.length - 1;
      } else {
        return false;
      }
    }
    onChangeEpisode(episodes[prevIndex]);
    return true;
  }

  /// 列表循环或者顺序播放时，自动播放下一个；自动连播时，播放相关视频
  @override
  bool nextPlay() {
    try {
      final episodes = _playbackEpisodes;
      if (episodes.isEmpty) return false;

      PlayRepeat playRepeat = videoDetailCtr.plPlayerController.playRepeat;

      int currentIndex = episodes.indexWhere(
        (e) => e.cid == videoDetailCtr.cid.value,
      );
      int nextIndex = currentIndex + 1;
      // 列表循环
      if (nextIndex >= episodes.length) {
        if (playRepeat == PlayRepeat.listCycle) {
          nextIndex = 0;
        } else {
          return false;
        }
      }
      onChangeEpisode(episodes[nextIndex]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> actionTriple() => showInteractionResult(
    interactions.triple(pgc: true, seasonId: seasonId, onAccepted: feedBack),
  );

  @override
  void close() {
    if (isClosed) return;
    _collection?.dispose();
    super.close();
  }

  Future<void> queryIsFollowed() =>
      isClosed ? Future.value() : collection.refreshTracking();

  @override
  void queryVideoIntro([EpisodeItem? episode]) {
    episode ??= pgcItem.episodes!.firstWhere((e) => e.cid == cid.value);
    videoDetail
      ..value.title = episode.showTitle
      ..refresh();
    videoPlayerServiceHandler?.onVideoDetailChange(
      episode,
      cid.value,
      heroTag,
      artist: pgcItem.title,
      navigation: mediaNavigation,
    );
  }

  Future<void> onFavPugv() =>
      showInteractionResult(collection.toggleBookmark());
}
