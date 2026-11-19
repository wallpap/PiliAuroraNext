import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final class LiveFeedback {
  LiveFeedback.capture(this.roomId) : _account = LiveHttp.recommend;

  final int? roomId;
  final Account _account;
  bool _submitting = false;

  bool get isCurrent => identical(_account, LiveHttp.recommend);

  Future<LoadingState<void>> submit(int? id, String? type) async {
    if (!isCurrent) return const Error('账号已切换，请重新打开反馈');
    if (_submitting) return const Error('正在提交反馈');
    final target = roomId;
    if (target == null || id == null || type == null) {
      return const Error('反馈信息不完整，请刷新后重试');
    }
    _submitting = true;
    try {
      return await LiveHttp.liveFeedback(target, id, type, account: _account);
    } finally {
      _submitting = false;
    }
  }
}
