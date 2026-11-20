import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/recommendation/result.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final class VideoFeedback {
  factory VideoFeedback.capture(BaseSimpleVideoItemModel item) {
    if (item is RcmdVideoItemAppModel) {
      return VideoFeedback._(
        AccountType.recommend,
        (id: item.param, type: item.goto),
        null,
      );
    }
    return VideoFeedback._(AccountType.main, null, item.bvid);
  }

  VideoFeedback._(this._role, this._appTarget, this._bvid)
    : _account = Accounts.get(_role);

  final AccountType _role;
  final Account _account;
  final ({int? id, String? type})? _appTarget;
  final String? _bvid;

  bool get isCurrent => identical(_account, Accounts.get(_role));

  String? get loginError => _account.accessKey?.isNotEmpty == true
      ? null
      : _account.isLogin
      ? '请退出账号后重新登录'
      : '账号未登录';

  Future<LoadingState<void>> submit({
    int? reasonId,
    int? feedbackId,
    bool cancel = false,
  }) async {
    if (!isCurrent) return const Error('账号已切换，请重新打开反馈');
    if (_appTarget case final target?) {
      final (:id, :type) = target;
      if (id == null || type == null) {
        return const Error('推荐反馈信息不完整，请刷新后重试');
      }
      return cancel
          ? VideoHttp.feedDislikeCancel(id: id, goto: type, account: _account)
          : VideoHttp.feedDislike(
              id: id,
              goto: type,
              reasonId: reasonId,
              feedbackId: feedbackId,
              account: _account,
            );
    }
    return VideoHttp.dislikeVideo(
      bvid: _bvid ?? '',
      type: !cancel,
      account: _account,
    );
  }
}
