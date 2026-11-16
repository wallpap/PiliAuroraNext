import 'dart:async' show FutureOr, Timer;

import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/audio_handler.dart'
    show MediaNavigation;
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/stat_detail.dart';
import 'package:pili_aurora_next/models/remote/video/video_tag/data.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class CommonIntroController extends GetxController
    with GetSingleTickerProviderStateMixin, TripleMixin, FavMixin {
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
  bool get isLogin => Accounts.main.isLogin;

  StatDetail? getStat();

  Object get interactionTarget => bvid;
  bool get interactionBusy => _interactionBusy;
  bool _interactionBusy = false;
  int interactionRevision = 0;

  bool ownsInteraction(Account account, Object target) =>
      !isClosed &&
      identical(account, Accounts.main) &&
      interactionTarget == target;

  /// 点赞、点踩、投币和三连会改动共同状态，串行执行并淘汰较早的状态查询。
  Future<void> runInteraction(
    Future<void> Function(Account account, bool Function() current) action,
  ) async {
    if (_interactionBusy || isClosed) return;
    final account = Accounts.main;
    if (!account.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final target = interactionTarget;
    bool current() => ownsInteraction(account, target);
    _interactionBusy = true;
    interactionRevision++;
    try {
      await action(account, current);
    } catch (error, stackTrace) {
      logger.w('视频互动未完成', error: error.runtimeType, stackTrace: stackTrace);
      if (current()) const UnknownResult().toast();
    } finally {
      _interactionBusy = false;
      interactionRevision++;
    }
  }

  @override
  Future<void> Function(int, bool) get payCoinCallback {
    final account = Accounts.main;
    final target = interactionTarget;
    return (coin, withLike) async {
      if (!ownsInteraction(account, target)) {
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
    final account = Accounts.main;
    return MediaNavigation(
      isCurrent: () =>
          !isClosed &&
          identical(account, Accounts.main) &&
          videoPlayerServiceHandler?.onPlay == null &&
          videoDetailCtr.playbackOwner.isActive,
      next: nextPlay,
      previous: prevPlay,
    );
  }

  void actionShareVideo(BuildContext context);

  // 同时观看
  final bool isShowOnlineTotal = Pref.enableOnlineTotal;
  late final RxString total = '1'.obs;
  Timer? timer;

  late final RxInt cid;

  late final videoDetailCtr = Get.find<VideoDetailController>(tag: heroTag);

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
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

  // 查看同时在看人数
  int _onlineQuery = 0;
  Future<void> queryOnlineTotal() async {
    if (!isShowOnlineTotal || isClosed) {
      return;
    }
    final version = ++_onlineQuery;
    final video = bvid;
    final part = cid.value;
    final account = Accounts.heartbeat;
    final result = await VideoHttp.onlineTotal(
      aid: IdUtils.bv2av(bvid),
      bvid: bvid,
      cid: cid.value,
    );
    if (isClosed ||
        version != _onlineQuery ||
        bvid != video ||
        cid.value != part ||
        !identical(account, Accounts.heartbeat)) {
      return;
    }
    if (result case Success(:final response)) {
      total.value = response;
    }
  }

  @override
  void onClose() {
    cancelTimer();
    super.onClose();
  }

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) async {
    await runInteraction((account, current) async {
      final limit = isHasCopyright(copyright) ? 2 : 1;
      if (coin > 0 && coinNum.value + coin > limit) {
        SmartDialog.showToast('达到投币上限啦~');
        return;
      }
      final res = await VideoHttp.coinVideo(
        bvid: bvid,
        multiply: coin,
        selectLike: coinWithLike ? 1 : 0,
        account: account,
      );
      // 余额属于发起账号；换视频后的已确认扣款仍然有效。
      if (res.isSuccess && identical(account, Accounts.main)) {
        GlobalData().afterCoin(coin);
      }
      if (!current()) return;
      if (res.isSuccess) {
        SmartDialog.showToast('投币成功');
        coinNum.value += coin;
        final stat = getStat();
        stat?.coin += coin;
        if (coinWithLike && !hasLike.value) {
          stat?.like++;
          hasLike.value = true;
        }
      } else {
        res.toast();
      }
    });
  }

  Future<void> queryVideoTags() async {
    final video = bvid;
    final part = cid.value;
    final account = Accounts.main;
    final result = await UserHttp.videoTags(bvid: bvid, cid: cid.value);
    if (isClosed ||
        bvid != video ||
        cid.value != part ||
        !identical(account, Accounts.main)) {
      return;
    }
    if (result case Success(:final response)) videoTags.value = response;
  }

  bool _savingLater = false;

  Future<void> viewLater() async {
    if (_savingLater || isClosed) return;
    final account = Accounts.main;
    final video = bvid;
    final removing = hasLater.value;
    _savingLater = true;
    try {
      final res = await (removing
          ? LaterLibrary.legacy.remove(
              [IdUtils.bv2av(video)],
              account: account,
            )
          : LaterLibrary.legacy.add(bvid: video, account: account));
      if (isClosed || bvid != video || !identical(account, Accounts.main)) {
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
  late final enableQuickFav = Pref.enableQuickFav;
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
    final account = Accounts.main;
    final target = getFavRidType;
    final source = favoriteOwner;
    if (!account.isLogin) {
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
          identical(account, Accounts.main) &&
          getFavRidType == target,
      onSaved: confirmedFavorite,
    );
  }

  Future<void> quickFavorite() async {
    if (_savingFav || isClosed) return;
    final account = Accounts.main;
    final target = getFavRidType;
    final source = favoriteOwner;
    bool current() =>
        !isClosed &&
        identical(source, favoriteOwner) &&
        identical(account, Accounts.main) &&
        getFavRidType == target;
    _savingFav = true;
    try {
      final result = await FavoriteLibrary.legacy.quick(
        account,
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
