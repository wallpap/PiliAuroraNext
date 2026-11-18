import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/music.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_detail.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class MusicDetailController extends CommonDynController {
  MusicDetailController({String? musicId})
    : musicId = musicId ?? Get.parameters['musicId'] ?? '';

  int _oid = 0;
  int _replyType = 47;
  @override
  int get oid => _oid;
  @override
  int get replyType => _replyType;

  bool get canComment => oid > 0;
  Account? _detailsAccount;
  int _detailsVersion = 0;
  final _updatingWish = false.obs;
  bool get updatingWish => _updatingWish.value;

  @override
  Object get sourceId => oid.toString();

  final infoState = LoadingState<MusicDetail>.loading().obs;

  final String musicId;

  String get shareUrl =>
      'https://music.bilibili.com/h5/music-detail?music_id=$musicId';

  @override
  void onInit() {
    super.onInit();
    Accounts.mainChanges.addListener(_accountChanged);
    getMusicDetail();
  }

  Future<void> getMusicDetail() async {
    if (isClosed) return;
    final version = ++_detailsVersion;
    final account = Accounts.main;
    if (infoState.value is Error) infoState.value = LoadingState.loading();
    bool current() =>
        !isClosed &&
        version == _detailsVersion &&
        identical(account, Accounts.main);
    try {
      final res = await MusicHttp.bgmDetail(musicId, account: account);
      if (!current()) {
        if (!isClosed && version == _detailsVersion) {
          infoState.value = const Error('账号已切换，请刷新音乐详情');
        }
        return;
      }
      if (res case Success(:final response)) {
        _detailsAccount = account;
        final comment = response.musicComment;
        _oid = comment?.oid ?? 0;
        _replyType = comment?.pageType ?? 47;
        count = canComment ? comment?.nums ?? -1 : 0;
        showComments();
      }
      infoState.value = res;
    } catch (error, stackTrace) {
      if (current()) infoState.value = Error.fromException(error, stackTrace);
    }
  }

  void _accountChanged() {
    _oid = 0;
    count = -1;
    commentSource.value = LoadingState.loading();
    infoState.value = LoadingState.loading();
    getMusicDetail();
  }

  @override
  Future<void> onReload() => getMusicDetail();

  Future<void> toggleWish(MusicDetail item) async {
    if (updatingWish ||
        isClosed ||
        !identical(infoState.value.dataOrNull, item)) {
      return;
    }
    final account = Accounts.main;
    if (!account.isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    if (!identical(_detailsAccount, account)) {
      SmartDialog.showToast('账号已更新，请刷新音乐详情后再操作');
      return;
    }
    final version = _detailsVersion;
    bool current() =>
        !isClosed &&
        version == _detailsVersion &&
        identical(account, Accounts.main) &&
        identical(infoState.value.dataOrNull, item);
    _updatingWish.value = true;
    try {
      final hasLike = item.wishListen ?? false;
      final result = await MusicHttp.wishUpdate(
        musicId,
        hasLike,
        account: account,
      );
      if (!current()) return;
      if (result.isSuccess) {
        final count = item.wishCount;
        if (count != null) {
          item.wishCount = hasLike ? (count > 0 ? count - 1 : 0) : count + 1;
        }
        item.wishListen = !hasLike;
        infoState.refresh();
      } else {
        result.toast();
      }
    } catch (error, stackTrace) {
      final failure = Error.fromException(error, stackTrace);
      if (current()) {
        UnknownResult(
          cause: failure.cause,
          stackTrace: failure.stackTrace,
        ).toast();
      }
    } finally {
      _updatingWish.value = false;
    }
  }

  @override
  void onClose() {
    Accounts.mainChanges.removeListener(_accountChanged);
    _detailsVersion++;
    super.onClose();
  }
}
