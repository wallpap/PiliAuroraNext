import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart'
    show PrivateId, SessionId, SessionUpdateReply;
import 'package:pili_aurora_next/grpc/im.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/msg.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_avatar.dart';
import 'package:pili_aurora_next/models/remote/msg/im_user_infos/datum.dart';
import 'package:pili_aurora_next/models/remote/msg/msg_dnd/uid_setting.dart';
import 'package:pili_aurora_next/models/remote/msg/session_ss/data.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/messaging/settings_adapter.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';

@immutable
class WhisperSettingsSnapshot {
  const WhisperSettingsSnapshot({
    required this.loadingState,
    this.title = '',
  });

  final LoadingState<Map<int, WhisperSetting>> loadingState;
  final String title;
}

class _SettingWrites {
  _SettingWrites(this.confirmed);

  WhisperSettingRecord confirmed;
  Future<void>? tail;
  int version = 0;
}

class WhisperSettingConfirmation {
  const WhisperSettingConfirmation._(this._session, this._key, this._record);

  final MessagingSession _session;
  final int _key;
  final WhisperSettingRecord _record;
}

class WhisperSettingsHandle {
  WhisperSettingsHandle({
    required this.session,
    required this.type,
  }) : state = ValueNotifier(
         WhisperSettingsSnapshot(
           loadingState: LoadingState.loading(),
         ),
       );

  final MessagingSession session;
  final WhisperSettingsSection type;
  final ValueNotifier<WhisperSettingsSnapshot> state;
  int _generation = 0;
  Map<int, WhisperSettingRecord> _records = {};
  final Map<int, _SettingWrites> _writes = {};
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed) return;
    if (_writes.isNotEmpty) {
      await Future.wait(_writes.values.map((writes) => writes.tail!));
      if (isActive) await refresh();
      return;
    }
    final generation = ++_generation;
    state.value = WhisperSettingsSnapshot(
      loadingState: LoadingState.loading(),
    );
    final result = await WhisperSettingsAdapter.load(session, type);
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Success(:final response) when isActive:
        _records = response.records;
        _publish(response.title);
      case Error():
        state.value = WhisperSettingsSnapshot(loadingState: result);
      default:
        break;
    }
  }

  Future<LoadingState<WhisperSettingConfirmation>> edit(
    int key,
    WhisperSettingEdit edit,
  ) async {
    final current = _records[key];
    if (!isActive || state.value.loadingState is! Success || current == null) {
      return const Error('当前操作不可用');
    }
    final desired = current.edit(edit);
    if (desired == null) return const Error('设置已更新，请重新选择');
    final writes = _writes.putIfAbsent(key, () => _SettingWrites(current));
    final version = ++writes.version;
    final previous = writes.tail;
    final completion = Completer<void>();
    writes.tail = completion.future;
    _generation++;
    _records[key] = desired;
    _publish(state.value.title);
    try {
      if (previous != null) await previous;
      if (!isActive) return const Error('账号已切换');
      final result = await WhisperSettingsAdapter.save(session, key, desired);
      if (!isActive) return const Error('账号已切换');
      if (result.isSuccess) {
        writes.confirmed = desired;
        session.notifyChanged(MessagingChangeKind.settings);
      }
      if (writes.version == version) {
        _generation++;
        _writes.remove(key);
        _records[key] = writes.confirmed;
        _publish(state.value.title);
      }
      final LoadingState<WhisperSettingConfirmation> confirmation =
          switch (result) {
            Success() => Success(
              WhisperSettingConfirmation._(session, key, desired),
            ),
            Error() => result,
            Loading() => result,
          };
      return confirmation;
    } finally {
      completion.complete();
    }
  }

  void mergeChild(int parentKey, WhisperSettingConfirmation child) {
    if (!isActive ||
        !identical(session, child._session) ||
        state.value.loadingState is! Success) {
      return;
    }
    final updated = _records[parentKey]?.withChild(child._key, child._record);
    if (updated == null) return;
    _records[parentKey] = updated;
    _publish(state.value.title);
  }

  void _publish(String title) {
    state.value = WhisperSettingsSnapshot(
      loadingState: Success(
        Map.unmodifiable({
          for (final entry in _records.entries) entry.key: entry.value.value,
        }),
      ),
      title: title,
    );
  }

  bool get isActive => !_disposed && session.isActive;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _writes.clear();
    _records.clear();
    state.dispose();
  }
}

@immutable
class ConversationSettingsSnapshot {
  const ConversationSettingsSnapshot({
    required this.userState,
    required this.sessionSs,
    required this.msgDnd,
    this.isPinned = false,
  });

  final LoadingState<List<ImUserInfosData>?> userState;
  final LoadingState<SessionSsData> sessionSs;
  final LoadingState<List<UidSetting>?> msgDnd;
  final bool isPinned;
}

class ConversationSettingsHandle {
  ConversationSettingsHandle({
    required this.session,
    required this.talkerUid,
  }) : state = ValueNotifier(
         ConversationSettingsSnapshot(
           userState: LoadingState<List<ImUserInfosData>?>.loading(),
           sessionSs: LoadingState<SessionSsData>.loading(),
           msgDnd: LoadingState<List<UidSetting>?>.loading(),
         ),
       );

  final MessagingSession session;
  final int talkerUid;
  final ValueNotifier<ConversationSettingsSnapshot> state;
  int _userGeneration = 0;
  int _sessionGeneration = 0;
  int _dndGeneration = 0;
  int _pinGeneration = 0;
  int _pushWriteVersion = 0;
  int _muteWriteVersion = 0;
  int _pinWriteVersion = 0;
  int _blockWriteVersion = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed || !session.isActive) return;
    await Future.wait([
      getUserInfo(),
      getSessionSs(),
      getMsgDnd(),
      getIsPinned(),
    ]);
  }

  Future<void> getUserInfo() async {
    final generation = ++_userGeneration;
    final result = await session.run(
      (account) => MsgHttp.imUserInfos(
        uids: talkerUid.toString(),
        account: account,
      ),
    );
    if (!_isCurrent(_userGeneration, generation)) return;
    state.value = _copy(userState: _mapLoadingState(result, _copyUser));
  }

  Future<void> getSessionSs() async {
    final generation = ++_sessionGeneration;
    final result = await session.run(
      (account) => MsgHttp.getSessionSs(
        talkerUid: talkerUid,
        account: account,
      ),
    );
    if (!_isCurrent(_sessionGeneration, generation)) return;
    state.value = _copy(sessionSs: _mapLoadingState(result, _copySessionSs));
  }

  Future<void> getMsgDnd() async {
    final generation = ++_dndGeneration;
    final result = await session.run(
      (account) => MsgHttp.getMsgDnd(
        uidsStr: talkerUid,
        account: account,
      ),
    );
    if (!_isCurrent(_dndGeneration, generation)) return;
    state.value = _copy(msgDnd: _mapLoadingState(result, _copyDnd));
  }

  Future<void> getIsPinned() async {
    final generation = ++_pinGeneration;
    final result = await session.run(
      (account) => ImGrpc.sessionUpdate(
        sessionId: _sessionId,
        account: account,
      ),
    );
    if (!_isCurrent(_pinGeneration, generation)) return;
    if (result case Success<SessionUpdateReply>(:final response)) {
      state.value = _copy(isPinned: response.session.isPinned);
    }
  }

  Future<LoadingState<void>> setPush(bool receivesPush) async {
    if (_disposed || !session.isActive) return const Error('当前操作不可用');
    final setting = receivesPush ? 1 : 0;
    final version = ++_pushWriteVersion;
    _sessionGeneration++;
    final result = await session.run(
      (account) => MsgHttp.setPushSs(
        setting: setting,
        talkerUid: talkerUid,
        account: account,
      ),
    );
    if (!_isActive) return const Error('账号已切换');
    if (result case Success<void>() when version == _pushWriteVersion) {
      _sessionGeneration++;
      final current = state.value.sessionSs.dataOrNull;
      if (current != null) {
        state.value = _copy(
          sessionSs: Success(_copySessionSs(current)..pushSetting = setting),
        );
      }
      session.notifyChanged(MessagingChangeKind.settings, talkerId: talkerUid);
    } else if (version == _pushWriteVersion) {
      _sessionGeneration++;
    }
    return result;
  }

  Future<LoadingState<void>> setPinned() async {
    if (_disposed || !session.isActive) return const Error('当前操作不可用');
    final next = !state.value.isPinned;
    final version = ++_pinWriteVersion;
    _pinGeneration++;
    final result = await session.run<void>(
      (account) => next
          ? ImGrpc.pinSession(sessionId: _sessionId, account: account)
          : ImGrpc.unpinSession(sessionId: _sessionId, account: account),
    );
    if (!_isActive) return const Error('账号已切换');
    if (result case Success<void>() when version == _pinWriteVersion) {
      _pinGeneration++;
      state.value = _copy(isPinned: next);
      session.notifyChanged(
        MessagingChangeKind.conversation,
        talkerId: talkerUid,
      );
    } else if (version == _pinWriteVersion) {
      _pinGeneration++;
    }
    return result;
  }

  Future<LoadingState<void>> setMuted(bool isMuted) async {
    if (_disposed || !session.isActive) return const Error('当前操作不可用');
    final setting = isMuted ? 0 : 1;
    final version = ++_muteWriteVersion;
    _dndGeneration++;
    final result = await session.run(
      (account) => MsgHttp.setMsgDnd(
        uid: account.mid,
        setting: setting,
        dndUid: talkerUid,
        account: account,
      ),
    );
    if (!_isActive) return const Error('账号已切换');
    if (result case Success<void>() when version == _muteWriteVersion) {
      _dndGeneration++;
      final current = state.value.msgDnd.dataOrNull;
      if (current != null && current.isNotEmpty) {
        final updated = _copyDnd(current)!;
        updated.first.setting = setting;
        state.value = _copy(msgDnd: Success(updated));
      }
      session.notifyChanged(
        MessagingChangeKind.conversation,
        talkerId: talkerUid,
      );
    } else if (version == _muteWriteVersion) {
      _dndGeneration++;
    }
    return result;
  }

  Future<LoadingState<void>> setBlocked(bool isBlocked) async {
    if (_disposed || !session.isActive) return const Error('当前操作不可用');
    final version = ++_blockWriteVersion;
    _sessionGeneration++;
    final result = await session.run(
      (account) => VideoHttp.relationMod(
        mid: talkerUid,
        act: isBlocked ? 6 : 5,
        reSrc: 11,
        account: account,
      ),
    );
    if (!_isActive) return const Error('账号已切换');
    if (result case Success<void>() when version == _blockWriteVersion) {
      _sessionGeneration++;
      final current = state.value.sessionSs.dataOrNull;
      if (current != null) {
        state.value = _copy(
          sessionSs: Success(
            _copySessionSs(current)..followStatus = isBlocked ? null : 128,
          ),
        );
      }
      session.notifyChanged(
        MessagingChangeKind.conversation,
        talkerId: talkerUid,
      );
    } else if (version == _blockWriteVersion) {
      _sessionGeneration++;
    }
    return result;
  }

  SessionId get _sessionId => SessionId(
    privateId: PrivateId(talkerUid: Int64(talkerUid)),
  );

  ConversationSettingsSnapshot _copy({
    LoadingState<List<ImUserInfosData>?>? userState,
    LoadingState<SessionSsData>? sessionSs,
    LoadingState<List<UidSetting>?>? msgDnd,
    bool? isPinned,
  }) => ConversationSettingsSnapshot(
    userState: userState ?? state.value.userState,
    sessionSs: sessionSs ?? state.value.sessionSs,
    msgDnd: msgDnd ?? state.value.msgDnd,
    isPinned: isPinned ?? state.value.isPinned,
  );

  static LoadingState<T> _mapLoadingState<T>(
    LoadingState<T> state,
    T Function(T) copy,
  ) => switch (state) {
    Success<T>(:final response) => Success(copy(response)),
    Error() => state,
    Loading() => state,
  };

  static List<ImUserInfosData>? _copyUser(List<ImUserInfosData>? items) => items
      ?.map(
        (item) => ImUserInfosData(
          mid: item.mid,
          name: item.name,
          face: item.face,
          sign: item.sign,
          vip: item.vip == null
              ? null
              : Vip.fromJson({
                  'type': item.vip!.type,
                  'status': item.vip!.status,
                  'label': item.vip!.label == null
                      ? null
                      : {'text': item.vip!.label!.text},
                }),
          pendant: item.pendant == null
              ? null
              : Pendant.fromJson({'image': item.pendant!.image}),
          official: item.official == null
              ? null
              : BaseOfficialVerify.fromJson({
                  'type': item.official!.type,
                  'desc': item.official!.desc,
                }),
        ),
      )
      .toList(growable: false);

  static SessionSsData _copySessionSs(SessionSsData item) => SessionSsData(
    followStatus: item.followStatus,
    pushSetting: item.pushSetting,
    showPushSetting: item.showPushSetting,
  );

  static List<UidSetting>? _copyDnd(List<UidSetting>? items) => items
      ?.map((item) => UidSetting(setting: item.setting))
      .toList(growable: false);

  bool get _isActive => !_disposed && session.isActive;
  bool _isCurrent(int currentGeneration, int generation) =>
      _isActive && currentGeneration == generation;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _userGeneration++;
    _sessionGeneration++;
    _dndGeneration++;
    _pinGeneration++;
    state.dispose();
  }
}
