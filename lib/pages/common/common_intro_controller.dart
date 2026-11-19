import 'dart:async' show FutureOr, Timer;
import 'dart:math' show max;

import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/playback/application/video_interaction.dart';
import 'package:pili_aurora_next/features/playback/application/video_details.dart';
import 'package:pili_aurora_next/services/audio_handler.dart'
    show MediaNavigation;
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/stat_detail.dart';
import 'package:pili_aurora_next/models/remote/video/video_tag/data.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/services/settings/display_preferences.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class CommonIntroController with TripleMixin, FavMixin {
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  @override
  late final TickerProvider tripleVsync;
  late final String heroTag;
  late String bvid;

  // 是否稍后再看
  late final RxBool hasLater;

  final Rx<List<VideoTagItem>?> videoTags = Rx<List<VideoTagItem>?>(null);

  bool isProcessing = false;
  Future<void> handleAction(FutureOr Function() action) async {
    if (!isProcessing) {
      isProcessing = true;
      try {
        await action();
      } finally {
        isProcessing = false;
      }
    }
  }

  @override
  bool get isLogin => AccountScope.signedIn;

  StatDetail? getStat();

  int? get interactionEpisode => null;
  bool get hasDisliked => false;
  set hasDisliked(bool value) {}
  late final interactions = VideoInteraction(
    target: () => isClosed ? null : (bvid: bvid, episode: interactionEpisode),
    read: () => (
      liked: hasLike.value,
      disliked: hasDisliked,
      coins: coinNum.value,
      favored: hasFav.value,
    ),
    publish: _publishReactions,
  );
  bool get interactionBusy => interactions.busy;

  void _publishReactions(VideoReactions state, {required bool fromQuery}) {
    final stat = getStat();
    if (stat != null) {
      if (fromQuery) {
        if (state.liked) stat.like = max(1, stat.like);
        if (state.favored) stat.favorite = max(1, stat.favorite);
      } else {
        if (state.liked != hasLike.value) stat.like += state.liked ? 1 : -1;
        if (state.favored != hasFav.value) {
          stat.favorite += state.favored ? 1 : -1;
        }
        stat.coin += max(0, state.coins - coinNum.value);
      }
    }
    hasLike.value = state.liked;
    hasDisliked = state.disliked;
    coinNum.value = state.coins;
    hasFav.value = state.favored;
  }

  Future<void> showInteractionResult(
    Future<LoadingState<String?>?> pending,
  ) async {
    final result = await pending;
    if (isClosed) return;
    if (result case Success(response: final String message)) {
      SmartDialog.showToast(message);
    } else if (result case Error()) {
      result.toast();
    }
  }

  @override
  Future<void> actionLikeVideo() =>
      showInteractionResult(interactions.toggleLike());

  @override
  Future<void> Function(int, bool) get payCoinCallback {
    final ownsPanel = interactions.captureOwner();
    return (coin, withLike) async {
      if (!ownsPanel()) {
        if (!isClosed) SmartDialog.showToast('视频或账号已更新，请重新打开投币面板');
        return;
      }
      await onPayCoin(coin, withLike);
    };
  }

  @override
  void updateFavCount(int count) {
    getStat()?.favorite += count;
  }

  final Rx<VideoDetailData> videoDetail = VideoDetailData().obs;

  void queryVideoIntro();

  bool prevPlay();
  bool nextPlay();

  MediaNavigation get mediaNavigation {
    final accountOwner = AccountScope.capture();
    return MediaNavigation(
      isCurrent: () =>
          !isClosed &&
          accountOwner.isCurrent &&
          videoPlayerServiceHandler?.onPlay == null &&
          videoDetailCtr.playbackOwner.isActive,
      next: nextPlay,
      previous: prevPlay,
    );
  }

  void actionShareVideo(BuildContext context);

  // 同时观看
  final bool isShowOnlineTotal = DisplayPreferences.showOnlineViewers;
  late final RxString total = '1'.obs;
  Timer? timer;

  late final RxInt cid;

  late final VideoDetailController videoDetailCtr;

  void open(VideoDetailController video, TickerProvider vsync) {
    videoDetailCtr = video;
    tripleVsync = vsync;
    final args = video.args;
    heroTag = args['heroTag'];
    bvid = args['bvid'];
    cid = RxInt(args['cid']);
    hasLater = RxBool(
      args['viewLater'] ?? args['sourceType'] == SourceType.watchLater,
    );

    queryVideoIntro();
    startTimer();
  }

  void startTimer() {
    if (isShowOnlineTotal) {
      queryOnlineTotal();
      timer ??= Timer.periodic(const Duration(seconds: 10), (Timer timer) {
        queryOnlineTotal();
      });
    }
  }

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  late final details = VideoDetails(
    video: () => isClosed ? null : bvid,
    part: () => cid.value,
    author: () => videoDetail.value.owner?.mid,
  );

  Future<void> queryOnlineTotal() async {
    if (!isShowOnlineTotal || isClosed) return;
    if (await details.online() case final value? when !isClosed) {
      total.value = value;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancelTimer();
    disposeTriple();
    videoDetail.close();
  }

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) => showInteractionResult(
    interactions.coin(
      coin,
      withLike: coinWithLike,
      limit: isHasCopyright(copyright) ? 2 : 1,
    ),
  );

  Future<void> queryVideoTags() async {
    if (isClosed) return;
    if (await details.tags() case Success(:final response) when !isClosed) {
      videoTags.value = response;
    }
  }

  bool _savingLater = false;

  Future<void> viewLater() async {
    if (_savingLater || isClosed) return;
    final accountOwner = AccountScope.capture();
    final video = bvid;
    final removing = hasLater.value;
    _savingLater = true;
    try {
      final res = await (removing
          ? LaterLibrary.legacy.remove(
              [IdUtils.bv2av(video)],
              account: accountOwner.account,
            )
          : LaterLibrary.legacy.add(
              bvid: video,
              account: accountOwner.account,
            ));
      if (isClosed || bvid != video || !accountOwner.isCurrent) {
        return;
      }
      if (res.isSuccess) {
        hasLater.value = !removing;
        SmartDialog.showToast(removing ? '已移除稍后再看' : '已添加到稍后再看');
      } else {
        res.toast();
      }
    } finally {
      _savingLater = false;
    }
  }
}

mixin FavMixin on TripleMixin {
  bool get isClosed;
  late final enableQuickFav = FavoriteLibrary.legacy.quickEnabled;
  bool _savingFav = false;
  (Object, int) get getFavRidType;
  Object get favoriteOwner => this;
  void updateFavCount(int count);

  void confirmedFavorite(bool value) {
    if (hasFav.value != value) {
      updateFavCount(value ? 1 : -1);
      hasFav.value = value;
    }
  }

  void showFavBottomSheet(BuildContext context, {bool isLongPress = false}) {
    final accountOwner = AccountScope.capture();
    final target = getFavRidType;
    final source = favoriteOwner;
    if (!accountOwner.account.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    if (enableQuickFav && !isLongPress) {
      quickFavorite();
      return;
    }
    if (!enableQuickFav && isLongPress) return;
    PageUtils.showFavBottomSheet(
      context: context,
      target: target,
      isCurrent: () =>
          !isClosed &&
          identical(source, favoriteOwner) &&
          accountOwner.isCurrent &&
          getFavRidType == target,
      onSaved: confirmedFavorite,
    );
  }

  Future<void> quickFavorite() async {
    if (_savingFav || isClosed) return;
    final accountOwner = AccountScope.capture();
    final target = getFavRidType;
    final source = favoriteOwner;
    bool current() =>
        !isClosed &&
        identical(source, favoriteOwner) &&
        accountOwner.isCurrent &&
        getFavRidType == target;
    _savingFav = true;
    try {
      final result = await FavoriteLibrary.legacy.quick(
        accountOwner.account,
        target,
        isCurrent: current,
      );
      if (!current()) return;
      if (result case Success(:final response)) {
        confirmedFavorite(response);
        SmartDialog.showToast(response ? '收藏成功' : '取消收藏成功');
      } else {
        result.toast();
      }
    } finally {
      _savingFav = false;
    }
  }
}
