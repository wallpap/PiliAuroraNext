import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class DraftEditorState<D> {
  const DraftEditorState({
    required this.draft,
    required this.inputKey,
    this.loading = false,
    this.saving = false,
    this.active = true,
    this.error,
  });
  final D draft;
  final Object inputKey;
  final bool loading, saving, active;
  final Error? error;
  DraftEditorState<D> copy({
    D? draft,
    Object? inputKey,
    bool? loading,
    bool? saving,
    bool? active,
    Error? error,
    bool clearError = false,
  }) => DraftEditorState(
    draft: draft ?? this.draft,
    inputKey: inputKey ?? this.inputKey,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    active: active ?? this.active,
    error: clearError ? null : error ?? this.error,
  );
}

/// 投票与预约共用账号归属、草稿保护和写入互斥，不拥有输入或导航资源。
abstract class AccountDraftEditor<D, R> extends Notifier<DraftEditorState<D>> {
  AccountDraftEditor(this.initialId);
  final int? initialId;
  int? remoteId;
  late Account _account;
  late DateTime now;
  int _loadGeneration = 0, _revision = 0;
  bool _disposed = false;
  D initialDraft(DateTime now);
  Future<LoadingState<D>> load(Account account, int id);
  Future<LoadingState<R>> save(Account account, int? id, D draft);
  int? savedId(R result);
  String? validate(D draft);
  DateTime get end => now.copyWith(day: now.day + 90);
  bool get isCurrent =>
      !_disposed &&
      ref.mounted &&
      state.active &&
      identical(_account, ref.read(mainAccountProvider));
  bool get canCreate =>
      isCurrent &&
      !state.loading &&
      state.error == null &&
      validate(state.draft) == null;
  @override
  DraftEditorState<D> build() {
    _disposed = false;
    now = DateTime.now();
    remoteId = initialId;
    _account = ref.read(mainAccountProvider);
    ref.listen(mainAccountProvider, (_, next) {
      if (!identical(_account, next)) {
        _loadGeneration++;
        state = state.copy(
          active: false,
          loading: false,
          saving: false,
          error: const Error('账号已切换，请重新打开编辑页'),
        );
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _loadGeneration++;
    });
    if (initialId != null) {
      scheduleMicrotask(() {
        if (!_disposed && ref.mounted) unawaited(queryData());
      });
    }
    return DraftEditorState(
      draft: initialDraft(now),
      inputKey: Object(),
      loading: initialId != null,
    );
  }

  void update(D Function(D) change) {
    if (!isCurrent) return;
    _revision++;
    state = state.copy(draft: change(state.draft));
  }

  Future<void> queryData() async {
    if (!isCurrent || remoteId == null || state.saving) return;
    final generation = ++_loadGeneration, revision = _revision;
    state = state.copy(loading: true, clearError: true);
    try {
      final result = await load(_account, remoteId!);
      if (!isCurrent || generation != _loadGeneration) return;
      if (revision != _revision) {
        state = state.copy(error: const Error('详情加载期间草稿已修改，请刷新核对后保存'));
      } else if (result case Success(:final response)) {
        _revision++;
        state = state.copy(
          draft: response,
          inputKey: Object(),
          clearError: true,
        );
      } else if (result case Error error) {
        state = state.copy(error: error);
      }
    } catch (cause, stack) {
      if (isCurrent && generation == _loadGeneration) {
        state = state.copy(error: Error.fromException(cause, stack));
      }
    } finally {
      if (isCurrent && generation == _loadGeneration) {
        state = state.copy(loading: false);
      }
    }
  }

  Future<LoadingState<R>> onCreate() async {
    if (!isCurrent) return const Error('账号已切换或页面已关闭，请重新打开');
    if (!_account.isLogin) return const Error('请先登录');
    if (state.saving) return const Error('正在保存，请稍候');
    if (!canCreate) {
      return Error(state.error?.errMsg ?? validate(state.draft) ?? '请等待详情加载');
    }
    final draft = state.draft;
    state = state.copy(saving: true);
    try {
      final result = await save(_account, remoteId, draft);
      if (!isCurrent) return const Error('账号已切换或页面已关闭');
      if (result case Success(:final response)) {
        remoteId = savedId(response) ?? remoteId;
      }
      return result;
    } catch (cause, stack) {
      return UnknownResult(cause: cause, stackTrace: stack);
    } finally {
      if (isCurrent) state = state.copy(saving: false);
    }
  }

  Account get account => _account;
}
