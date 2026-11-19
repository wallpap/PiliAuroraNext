import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/messaging/providers.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/messaging/settings_adapter.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';

final blockedKeywordsProvider = Provider.autoDispose((ref) {
  final handle = BlockedKeywordsHandle(ref.watch(messagingSessionProvider));
  ref.onDispose(handle.dispose);
  scheduleMicrotask(handle.refresh);
  return handle;
});

class BlockedKeywordsHandle {
  BlockedKeywordsHandle(this._session);

  final MessagingSession _session;
  final _state = ValueNotifier<LoadingState<BlockedKeywords>>(
    LoadingState.loading(),
  );
  ValueListenable<LoadingState<BlockedKeywords>> get state => _state;

  int _generation = 0;
  bool _disposed = false;
  bool get isActive => !_disposed && _session.isActive;
  final _writes = <String>{};
  bool _refreshAfterWrites = false;

  Future<void> refresh() async {
    if (_disposed) return;
    if (_writes.isNotEmpty) {
      _refreshAfterWrites = true;
      return;
    }
    final generation = ++_generation;
    _state.value = LoadingState.loading();
    final result = await BlockedKeywordsAdapter.load(_session);
    if (!_disposed && generation == _generation) _state.value = result;
  }

  Future<LoadingState<void>> setBlocked(
    String word, {
    required bool blocked,
  }) async {
    if (!isActive || _state.value is! Success) {
      return const Error('当前操作不可用');
    }
    if (!_writes.add(word)) return const Error('请等待当前操作完成');
    try {
      final result = await BlockedKeywordsAdapter.write(
        _session,
        word,
        blocked: blocked,
      );
      if (!isActive) return const Error('账号已切换');
      if (result.isSuccess) {
        final current = _state.value.data;
        final words = List<String>.unmodifiable([
          for (final item in current.words)
            if (item != word) item,
          if (blocked) word,
        ]);
        _state.value = Success((
          words: words,
          listLimit: current.listLimit,
          charLimit: current.charLimit,
        ));
        _session.notifyChanged(MessagingChangeKind.settings);
      }
      return result;
    } finally {
      _writes.remove(word);
      if (isActive && _writes.isEmpty && _refreshAfterWrites) {
        _refreshAfterWrites = false;
        unawaited(refresh());
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state.dispose();
  }
}
