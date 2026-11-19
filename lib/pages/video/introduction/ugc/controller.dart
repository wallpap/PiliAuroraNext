import 'dart:async';

import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadMixin;
import 'package:pili_aurora_next/features/playback/application/video_details.dart';
import 'package:pili_aurora_next/http/constants.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/remote/member_card_info/data.dart';
import 'package:pili_aurora_next/models/remote/relation/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_ai_conclusion/model_result.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/dimension.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/episode.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/page.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/staff.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/stat_detail.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/android/android_helper.dart';
import 'package:pili_aurora_next/utils/device_utils.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/features/following/presentation/follow_actions_dialog.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class UgcIntroController extends CommonIntroController with ReloadMixin {
  late final RxBool expand;
  final RxBool status = true.obs;

  // up主粉丝数
  final Rx<MemberCardInfoData> userStat = MemberCardInfoData().obs;
  // 关注状态 默认未关注
  late final Rx<RelationData> followStatus = Rx(RelationData());
  late final RxMap staffRelations = {}.obs;

  // 是否点踩
  final RxBool hasDislike = false.obs;

  late final showArgueMsg = Pref.showArgueMsg;
  late final enableAi = Pref.enableAi;
  late final horizontalMemberPage = Pref.horizontalMemberPage;

  AiConclusionResult? aiConclusionResult;

  late final Map<int?, bool> seasonFavState = {};

  @override
  void open(VideoDetailController video, TickerProvider vsync) {
    super.open(video, vsync);
    final alwaysExpandIntroPanel = Pref.alwaysExpandIntroPanel;
    expand = RxBool(alwaysExpandIntroPanel);
    if (!alwaysExpandIntroPanel && Pref.expandIntroPanelH) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed && !expand.value && !DeviceUtils.size.isPortrait) {
          expand.toggle();
        }
      });
    }
    videoDetail.value.title = video.args['title'] ?? '';
  }

  @override
  Future<void> queryVideoIntro() async {
    if (isClosed) return;
    queryVideoTags();
    final res = await details.introduction();
    if (res == null || isClosed) return;
    if (res case Success(:final response)) {
      if (response.redirectUrl != null &&
          videoDetailCtr.epId == null &&
          videoDetailCtr.seasonId == null) {
        if (!isClosed) {
          PageUtils.viewPgcFromUri(response.redirectUrl!, off: true);
        }
        return;
      }
      videoPlayerServiceHandler?.onVideoDetailChange(
        response,
        cid.value,
        heroTag,
        navigation: mediaNavigation,
      );
      VideoDetails.retainEpisodeOrder(videoDetail.value, response);
      videoDetail.value = response;
      status.value = true;
      try {
        if (videoDetailCtr.cover.value.isEmpty ||
            (videoDetailCtr.videoUrl.isNullOrEmpty &&
                !videoDetailCtr.isQuerying)) {
          videoDetailCtr.cover.value = response.pic ?? '';
        }
        videoDetailCtr.onReplyCount?.call(response.stat?.reply ?? 0);
      } catch (_) {}
      final pages = videoDetail.value.pages;
      if (pages != null && pages.isNotEmpty && cid.value == 0) {
        cid.value = pages.first.cid!;
      }
      queryUserStat(response.staff);
    } else {
      res.toast();
      status.value = false;
    }

    if (isLogin) {
      queryAllStatus();
      queryFollowStatus();
    }
  }

  Future<void> queryUserStat(List<Staff>? staff) async {
    final stats = await details.authorStats(staff);
    if (stats == null || isClosed) return;
    if (stats.staff case final relations?) {
      staffRelations.assignAll({'status': true, ...relations});
    } else if (stats.profile case final profile?) {
      userStat.value = profile;
    }
  }

  @override
  bool get hasDisliked => hasDislike.value;
  @override
  set hasDisliked(bool value) => hasDislike.value = value;

  Future<void> queryAllStatus() async {
    await interactions.refresh(pgc: false);
  }

  @override
  Future<void> actionTriple() => showInteractionResult(
    interactions.triple(pgc: false, onAccepted: feedBack),
  );

  Future<void> actionDislikeVideo() =>
      showInteractionResult(interactions.toggleDislike());

  @override
  int get copyright => videoDetail.value.copyright ?? 1;

  @override
  (Object, int) get getFavRidType => (IdUtils.bv2av(bvid), 2);

  @override
  StatDetail? getStat() => videoDetail.value.stat;

  // 分享视频
  @override
  void actionShareVideo(BuildContext context) {
    final accountOwner = AccountScope.capture();
    bool ownsAccount() =>
        context.mounted && !isClosed && accountOwner.isCurrent;
    final videoDetail = this.videoDetail.value;
    final cid = this.cid.value;
    final partIndex = videoDetail.pages?.indexWhere((e) => e.cid == cid);
    final addIndex = partIndex != null && partIndex > 0;
    final playedTimePos = videoDetailCtr.playedTimePos(addIndex);
    final videoUrl =
        '${HttpString.baseUrl}/video/$bvid/${addIndex ? '?p=${partIndex + 1}' : ''}';
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text(
              '复制链接',
              style: TextStyle(fontSize: 14),
            ),
            onTap: () {
              Get.back();
              Utils.copyText(videoUrl);
            },
            trailing: playedTimePos.isNotEmpty
                ? iconButton(
                    tooltip: '精确分享',
                    icon: const Icon(Icons.timer_outlined),
                    onPressed: () {
                      Get.back();
                      Utils.copyText('$videoUrl$playedTimePos');
                    },
                  )
                : null,
          ),
          ListTile(
            dense: true,
            title: const Text(
              '其它app打开',
              style: TextStyle(fontSize: 14),
            ),
            onTap: () {
              Get.back();
              PiliAndroidHelper.openUrl(videoUrl);
            },
          ),
          if (PlatformUtils.isMobile)
            ListTile(
              dense: true,
              title: const Text(
                '分享视频',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                Get.back();
                ShareUtils.shareText(
                  '${videoDetail.title} '
                  'UP主: ${videoDetail.owner!.name!}'
                  ' - $videoUrl',
                );
              },
            ),
          if (isLogin)
            ListTile(
              dense: true,
              title: const Text(
                '分享至动态',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                Get.back();
                if (!ownsAccount()) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (context) => RepostPanel(
                    rid: videoDetail.aid,
                    dynType: 8,
                    pic: videoDetail.pic,
                    title: videoDetail.title,
                    uname: videoDetail.owner?.name,
                  ),
                );
              },
            ),
          if (isLogin)
            ListTile(
              dense: true,
              title: const Text(
                '分享至消息',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () async {
                Get.back();
                if (!ownsAccount()) return;
                try {
                  await PageUtils.pmShare(
                    context,
                    content: {
                      "id": videoDetail.aid!.toString(),
                      "title": videoDetail.title!,
                      "headline": videoDetail.title!,
                      "source": 5,
                      "thumb": videoDetail.pic!,
                      "author": videoDetail.owner!.name!,
                      "author_id": videoDetail.owner!.mid!.toString(),
                    },
                  );
                } catch (error, stack) {
                  logger.w(
                    '打开视频分享失败',
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

  Future<void> queryFollowStatus() async {
    final detail = videoDetail.value;
    final mid = detail.owner?.mid;
    if (mid == null || detail.staff?.isNotEmpty == true) return;
    if (await details.followStatus(mid) case final relation? when !isClosed) {
      followStatus.value = relation;
    }
  }

  // 关注/取关up
  Future<void> actionRelationMod(BuildContext context) async {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final videoDetail = this.videoDetail.value;
    if (videoDetail.staff?.isNotEmpty == true) {
      return;
    }
    final mid = videoDetail.owner?.mid;
    if (mid == null) {
      return;
    }
    final attr = followStatus.value.attribute ?? 0;
    if (attr == 128) {
      if (await details.unblock(mid) && !isClosed) {
        followStatus
          ..value.attribute = 0
          ..refresh();
      }
      return;
    } else {
      final current = details.captureAuthor(mid);
      showFollowActions(
        context: context,
        mid: mid,
        isFollow: attr != 0,
        followStatus: followStatus.value,
        isCurrent: current,
        afterMod: (attribute) {
          details.invalidateRelation();
          followStatus
            ..value.attribute = attribute
            ..refresh();
          Timer(const Duration(milliseconds: 500), () {
            if (current()) queryFollowStatus();
          });
        },
      );
    }
  }

  // 修改分P或番剧分集
  int _episodeChange = 0;
  void Function(String bvid)? onRelatedTargetChanged;
  bool Function(bool Function() isCurrent)? onPlayRelated;

  Future<bool> onChangeEpisode(
    BaseEpisodeItem episode, {
    bool isStein = false,
  }) async {
    if (isClosed) return false;
    final version = ++_episodeChange;
    final playbackAccount = AccountScope.captureHeartbeat();
    final mainAccount = AccountScope.capture();
    final source = (bvid, cid.value);
    final videoSource = (videoDetailCtr.bvid, videoDetailCtr.cid.value);
    final ownsPlayback = videoDetailCtr.playbackOwner.guard();
    bool current() =>
        !isClosed &&
        version == _episodeChange &&
        playbackAccount.isCurrent &&
        mainAccount.isCurrent &&
        source == (bvid, cid.value) &&
        videoSource == (videoDetailCtr.bvid, videoDetailCtr.cid.value) &&
        ownsPlayback();
    try {
      if (!current()) return false;
      final String bvid = episode.bvid ?? this.bvid;
      final int aid = episode.aid ?? IdUtils.bv2av(bvid);
      int? cid = episode.cid;
      final String? cover = episode.cover;
      Dimension? dimension;
      if (cid == null || cid <= 0) {
        final result = await VideoDetails.resolvePart(
          playbackAccount.account,
          bvid,
          aid,
        );
        if (!current()) return false;
        if (result is Error) {
          result.toast();
          return false;
        }
        cid = result.dataOrNull?.cid;
        dimension = result.dataOrNull?.dimension;
      }
      if (!current()) return false;
      if (cid == null || cid <= 0) {
        SmartDialog.showToast('该视频暂无可播放分 P');
        return false;
      }

      // 重新获取视频资源
      if (videoDetailCtr.isPlayAll) {
        if (videoDetailCtr.mediaList.indexWhere((item) => item.bvid == bvid) ==
            -1) {
          if (dimension == null && episode is EpisodeItem) {
            dimension = episode.page?.dimension;
          }
          PageUtils.toVideoPage(
            bvid: bvid,
            cid: cid,
            cover: cover,
            dimension: dimension,
            title: episode.title,
          );
          return false;
        }
      }

      videoDetailCtr
        ..inheritedSubtitleEnabled =
            Pref.inheritSubtitleState && bvid == this.bvid
            ? videoDetailCtr.vttSubtitlesIndex.value > 0
            : null
        ..plPlayerController.pause()
        ..makeHeartBeat()
        ..updateMediaListHistory(aid)
        ..onReset(isStein: isStein)
        ..bvid = bvid
        ..aid = aid
        ..cid.value = cid
        ..queryVideoUrl();

      if (this.bvid != bvid) {
        reload = true;
        aiConclusionResult = null;

        if (cover != null && cover.isNotEmpty) {
          videoDetailCtr.cover.value = cover;
        }

        videoDetailCtr.onReplyTargetChanged?.call();

        hasLater.value = videoDetailCtr.sourceType == SourceType.watchLater;
        this.bvid = bvid;
        queryVideoIntro();
      } else {
        if (episode is Part) {
          final videoDetail = this.videoDetail.value;
          videoPlayerServiceHandler?.onVideoDetailChange(
            episode,
            cid,
            heroTag,
            artist: videoDetail.owner?.name,
            cover: videoDetail.pic,
            navigation: mediaNavigation,
          );
        }
      }

      this.cid.value = cid;
      onRelatedTargetChanged?.call(bvid);
      queryOnlineTotal();
      return true;
    } catch (e, stackTrace) {
      logger.w('切换视频分 P 失败', error: e.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('切换分 P 失败，请重试');
      return false;
    }
  }

  @override
  bool prevPlay([bool skipPart = false]) =>
      _playAdjacent(forward: false, skipPart: skipPart);

  @override
  bool nextPlay([bool skipPart = false]) =>
      _playAdjacent(forward: true, skipPart: skipPart);

  bool _playAdjacent({required bool forward, required bool skipPart}) {
    final detail = videoDetail.value;
    final parts = detail.pages;
    final isPart = !skipPart && parts != null && parts.length > 1;
    final playAll = videoDetailCtr.isPlayAll;
    final player = videoDetailCtr.plPlayerController;
    final repeat = player.playRepeat;
    final episodes = isPart
        ? parts
        : playAll
        ? videoDetailCtr.mediaList
        : <BaseEpisodeItem>[
            for (final section in detail.ugcSeason?.sections ?? const [])
              ...?section.episodes,
          ];
    if (episodes.isEmpty) {
      if (!forward) return false;
      if (repeat == PlayRepeat.listCycle) {
        player.play(repeat: true);
        return true;
      }
      return repeat == PlayRepeat.autoPlayRelated &&
          player.showRelatedVideo &&
          playRelated();
    }

    final currentCid = cid.value;
    final anchor = skipPart
        ? (detail.isPageReversed ? parts?.lastOrNull : parts?.firstOrNull)
                  ?.cid ??
              currentCid
        : currentCid;
    final currentIndex = episodes.indexWhere(
      (episode) => episode.cid == anchor,
    );
    if (forward &&
        !isPart &&
        playAll &&
        currentIndex >= 0 &&
        currentIndex == episodes.length - 2) {
      videoDetailCtr.getMediaList();
    }

    final step = forward ? 1 : -1;
    var index = currentIndex < 0 ? (forward ? 0 : -1) : currentIndex + step;
    if (index < 0 || index >= episodes.length) {
      if (isPart && (playAll || detail.ugcSeason != null)) {
        return _playAdjacent(forward: forward, skipPart: true);
      }
      if (repeat == PlayRepeat.listCycle) {
        index = forward ? 0 : episodes.length - 1;
      } else {
        return forward &&
            repeat == PlayRepeat.autoPlayRelated &&
            player.showRelatedVideo &&
            playRelated();
      }
    }

    for (; index >= 0 && index < episodes.length; index += step) {
      final episode = episodes[index];
      final targetCid = episode.cid;
      if (targetCid == null) continue;
      if (targetCid == currentCid) return false;
      onChangeEpisode(episode);
      return true;
    }
    return false;
  }

  bool playRelated() {
    final version = _episodeChange;
    final ownsPlayback = videoDetailCtr.playbackOwner.guard();
    return onPlayRelated?.call(
          () => !isClosed && version == _episodeChange && ownsPlayback(),
        ) ??
        false;
  }

  // ai总结
  static Future<AiConclusionResult?> getAiConclusion(
    String bvid,
    int cid,
    int? mid,
  ) async {
    if (!AccountScope.captureHeartbeat().account.isLogin) {
      SmartDialog.showToast("账号未登录");
      return null;
    }
    SmartDialog.showLoading(msg: '正在获取AI总结');
    final res = await VideoDetails.summary(bvid, cid, mid);
    unawaited(
      SmartDialog.dismiss(status: .loading)
          .catchError((Object error, StackTrace stackTrace) {
            logger.w(
              '关闭 AI 总结加载提示失败',
              error: error.runtimeType,
              stackTrace: stackTrace,
            );
          }),
    );
    if (res == null) return null;
    if (res case Success(:final response)) {
      return response;
    } else if (res is Error && res.code == 1) {
      SmartDialog.showToast("AI处理中，请稍后再试");
    } else {
      res.toast();
    }
    return null;
  }

  Future<void> aiConclusion() async {
    final video = bvid;
    final part = cid.value;
    final playbackAccount = AccountScope.captureHeartbeat();
    final result = await getAiConclusion(
      bvid,
      cid.value,
      videoDetail.value.owner?.mid,
    );
    if (!isClosed &&
        video == bvid &&
        part == cid.value &&
        playbackAccount.isCurrent) {
      aiConclusionResult = result;
    }
  }
}
