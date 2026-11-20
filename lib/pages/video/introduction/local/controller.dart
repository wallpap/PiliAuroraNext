import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/stat_detail.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/desktop_playback_windows.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/foundation.dart' show kDebugMode, ValueNotifier;
import 'package:flutter/scheduler.dart' show SchedulerBinding, TickerProvider;

class LocalIntroController extends CommonIntroController {
  @override
  void queryVideoIntro() {}

  @override
  int get copyright => throw UnimplementedError();

  @override
  Future<void> actionLikeVideo() async {}

  @override
  void actionShareVideo(context) {}

  @override
  void actionTriple() {}

  @override
  Future<void> quickFavorite() async {}

  @override
  (Object, int) get getFavRidType => throw UnimplementedError();

  @override
  StatDetail? getStat() => null;

  @override
  bool get isShowOnlineTotal => false;

  late final Set<String> aidSet = {};

  @override
  void close() {
    if (isClosed) return;
    aidSet.clear();
    super.close();
    index.dispose();
    list.dispose();
  }

  @override
  void open(VideoDetailController video, TickerProvider vsync) {
    super.open(video, vsync);
    videoDetail.value = VideoDetailData(title: videoDetailCtr.args['title']);
    if (DesktopPlaybackWindows.isPlayerWindow) {
      this.list.value = [videoDetailCtr.entry];
      this.index.value = 0;
      return;
    }
    // 离线入口固定播放列表，播放页不再依赖下载首页的存活与注册。
    final supplied = videoDetailCtr.args['offlineEntries'];
    final list = supplied is List<BiliDownloadEntryInfo> && supplied.isNotEmpty
        ? supplied.toList()
        : <BiliDownloadEntryInfo>[videoDetailCtr.entry];
    final counts = <String, int>{};
    for (final entry in list) {
      counts.update(entry.pageId, (count) => count + 1, ifAbsent: () => 1);
    }
    aidSet.addAll(
      counts.entries
          .where((entry) => entry.value == 1)
          .map((entry) => entry.key),
    );
    this.list.value = list;
    final currCid = videoDetailCtr.cid.value;
    final found = list.indexWhere((e) => e.cid == currCid);
    final index = found < 0 ? 0 : found;
    this.index.value = index;
    if (PlatformUtils.isMobile) {
      onVideoDetailChange(list[index]);
    }
    if (index != 0) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          final state = videoDetailCtr.scrollKey.currentState;
          if (state != null && state.mounted) {
            (state.innerController as ExtendedNestedScrollController)
                .nestedPositions
                .first
                .localJumpTo(_offset);
          } else if (videoDetailCtr.introScrollCtr?.hasClients ?? false) {
            videoDetailCtr.introScrollCtr!.jumpTo(_offset);
          }
        } catch (_) {
          if (kDebugMode) rethrow;
        }
      });
    }
  }

  final index = ValueNotifier(-1);
  double get _offset => index.value * 112.0 + 7 - 35;
  final list = ValueNotifier<List<BiliDownloadEntryInfo>>(const []);

  @override
  bool nextPlay() {
    final next = index.value + 1;
    if (next < list.value.length) {
      playIndex(next);
      return true;
    } else {
      final playCtr = videoDetailCtr.plPlayerController;
      if (playCtr.playRepeat == PlayRepeat.listCycle) {
        if (list.value.length == 1) {
          playCtr.seek(Duration.zero).whenComplete(playCtr.play);
        } else {
          playIndex(0);
        }
        return true;
      }
    }
    return false;
  }

  @override
  bool prevPlay() {
    final prev = index.value - 1;
    if (prev >= 0) {
      playIndex(prev);
      return true;
    }
    return false;
  }

  void playIndex(
    int index, {
    BiliDownloadEntryInfo? entry,
  }) {
    entry ??= list.value[index];
    videoDetailCtr
      ..onReset()
      ..cover.value = entry.cover
      ..aid = entry.avid
      ..bvid = entry.bvid
      ..cid.value = entry.cid
      ..args['dirPath'] = entry.entryDirPath
      ..initFileSource(entry, isInit: false)
      ..playerInit();
    videoDetail.value = VideoDetailData(title: entry.showTitle);
    this.index.value = index;
    if (PlatformUtils.isMobile) {
      onVideoDetailChange(entry);
    }
  }

  void onVideoDetailChange(BiliDownloadEntryInfo entry) {
    videoPlayerServiceHandler?.onVideoDetailChange(
      entry,
      entry.cid,
      heroTag,
      navigation: mediaNavigation,
    );
  }
}
