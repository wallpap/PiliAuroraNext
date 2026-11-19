import 'dart:async';

import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_superchat/item.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart'
    show LiveDanmaku;
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class LiveRoomInteractions {
  LiveRoomInteractions(int room, {required this._roomIsCurrent})
    : _room = room,
      _account = Accounts.main;

  final int _room;
  final bool Function() _roomIsCurrent;
  final Account _account;

  bool get isLogin => _account.isLogin;
  bool get isCurrent => _roomIsCurrent() && identical(_account, Accounts.main);
  static const _stale = Error('直播间或账号已更新');

  Future<LoadingState<void>?> send(
    String message, {
    int? dmType,
    Object? emoticonOptions,
    int replyMid = 0,
    String replyId = '',
  }) async {
    if (!isCurrent || message.trim().isEmpty) return null;
    final result = await LiveHttp.sendLiveMsg(
      account: _account,
      roomId: _room,
      msg: message,
      dmType: dmType,
      emoticonOptions: emoticonOptions,
      replyMid: replyMid,
      replayDmid: replyId,
      canSend: () => isCurrent,
    );
    return isCurrent ? result : null;
  }

  Future<LoadingState<void>?> shield(Object uid) async {
    if (!isCurrent || !isLogin) return null;
    final result = await LiveHttp.liveShieldUser(
      account: _account,
      uid: uid,
      roomid: _room,
      type: 1,
    );
    if (!isCurrent) return null;
    return result.isSuccess ? const Success(null) : result as Error;
  }

  Future<LoadingState<void>> reportMessage(
    String message,
    LiveDanmaku source, {
    required int reasonId,
    required String reason,
  }) {
    if (!isCurrent || !isLogin) return Future.value(_stale);
    return LiveHttp.liveDmReport(
      account: _account,
      roomId: _room,
      mid: source.mid,
      msg: message,
      reason: reason,
      reasonId: reasonId,
      dmType: source.dmType,
      idStr: source.id,
      ts: source.ts,
      sign: source.ct,
    );
  }

  Future<LoadingState<void>> reportSuperChat(
    SuperChatItem item,
    String reason,
  ) {
    if (!isCurrent || !isLogin) return Future.value(_stale);
    return LiveHttp.superChatReport(
      account: _account,
      id: item.id,
      roomId: _room,
      uid: item.uid,
      msg: item.message,
      reason: reason,
      ts: item.ts,
      token: item.token,
    );
  }
}

typedef _LikeTarget = ({int room, Account viewer, Account heartbeat});

class LiveRoomLikes {
  LiveRoomLikes({
    required this.room,
    required this.anchor,
    required this.onCount,
    required this.onReceipt,
  });

  final int? Function() room;
  final int? Function() anchor;
  final void Function(int) onCount;
  final void Function(LoadingState<void>) onReceipt;
  _LikeTarget? _queuedTarget;
  int _queuedCount = 0;
  Timer? _timer;
  bool _ready = false;
  bool _sending = false;
  bool _disposed = false;

  bool _owns(_LikeTarget target) =>
      !_disposed &&
      room() == target.room &&
      identical(Accounts.main, target.viewer) &&
      identical(Accounts.heartbeat, target.heartbeat);

  void tapDown() {
    final id = room();
    if (_disposed || id == null) return;
    _timer?.cancel();
    _timer = null;
    _ready = false;
    final target = _queuedTarget;
    if (target == null || !_owns(target)) {
      _queuedTarget = (
        room: id,
        viewer: Accounts.main,
        heartbeat: Accounts.heartbeat,
      );
      _queuedCount = 0;
    }
    onCount(++_queuedCount);
  }

  void tapUp() {
    if (_disposed || _ready || _queuedCount == 0) return;
    _timer ??= Timer(const Duration(milliseconds: 800), () {
      _timer = null;
      _ready = true;
      unawaited(_send());
    });
  }

  Future<void> _send() async {
    if (_sending || !_ready) return;
    final target = _queuedTarget;
    final clicks = _queuedCount;
    _queuedTarget = null;
    _queuedCount = 0;
    _ready = false;
    if (target == null || !target.viewer.isLogin || !_owns(target)) {
      if (!_disposed) onCount(0);
      return;
    }
    _sending = true;
    try {
      final result = await LiveHttp.liveLikeReport(
        clickTime: clicks,
        roomId: target.room,
        uid: target.viewer.mid,
        account: target.heartbeat,
        anchorId: anchor(),
        canSend: () => _owns(target),
      );
      if (_owns(target)) onReceipt(result);
    } finally {
      _sending = false;
      if (!_disposed && _queuedCount == 0) onCount(0);
      if (_ready) unawaited(_send());
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _ready = false;
  }
}
