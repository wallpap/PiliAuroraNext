import 'package:pili_aurora_next/features/community/application/content_page_detail.dart';
import 'package:pili_aurora_next/features/community/domain/comment_share_origin.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/application/music_queries.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_detail.dart';
import 'package:pili_aurora_next/utils/accounts.dart';

class MusicDetailController extends ContentPageDetail {
  MusicDetailController({required this.musicId, super.onFeedback});

  int _oid = 0;
  int _replyType = 47;
  @override
  int get oid => _oid;
  @override
  int get replyType => _replyType;

  bool get canComment => oid > 0;
  Account? _detailsAccount;
  int _detailsVersion = 0;
  final wishPending = DetailValue(false);
  bool get updatingWish => wishPending.value;

  @override
  Object get sourceId => oid.toString();

  final infoState = DetailValue(LoadingState<MusicDetail>.loading());

  final String musicId;

  String get shareUrl =>
      'https://music.bilibili.com/h5/music-detail?music_id=$musicId';

  CommentShareOrigin get commentShare {
    final detail = infoState.value.dataOrNull;
    return (
      url: shareUrl,
      cover: detail?.mvCover,
      title: detail?.musicTitle,
      published: detail?.musicPublish,
    );
  }

  @override
  void open() {
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
      final res = await MusicQueries.detail(account, musicId);
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
      onFeedback?.call('请先登录');
      return;
    }
    if (!identical(_detailsAccount, account)) {
      onFeedback?.call('账号已更新，请刷新音乐详情后再操作');
      return;
    }
    final version = _detailsVersion;
    bool current() =>
        !isClosed &&
        version == _detailsVersion &&
        identical(account, Accounts.main) &&
        identical(infoState.value.dataOrNull, item);
    wishPending.value = true;
    try {
      final hasLike = item.wishListen ?? false;
      final result = await MusicQueries.setWish(account, musicId, hasLike);
      if (!current()) return;
      if (result.isSuccess) {
        final count = item.wishCount;
        if (count != null) {
          item.wishCount = hasLike ? (count > 0 ? count - 1 : 0) : count + 1;
        }
        item.wishListen = !hasLike;
        infoState.refresh();
      } else {
        onFeedback?.call(result.toString());
      }
    } catch (error, stackTrace) {
      final failure = Error.fromException(error, stackTrace);
      if (current()) {
        onFeedback?.call(
          UnknownResult(
            cause: failure.cause,
            stackTrace: failure.stackTrace,
          ).toString(),
        );
      }
    } finally {
      if (!isClosed) wishPending.value = false;
    }
  }

  @override
  void close() {
    if (isClosed) return;
    Accounts.mainChanges.removeListener(_accountChanged);
    _detailsVersion++;
    infoState.dispose();
    wishPending.dispose();
    super.close();
  }
}
