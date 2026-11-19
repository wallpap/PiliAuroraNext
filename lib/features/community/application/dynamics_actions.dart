import 'dart:collection';
import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final dynamicsActionsProvider = Provider(
  (ref) => DynamicsActions(
    ref.read(dynamicsRepositoryProvider),
    ref.read(dynamicsUpdatesProvider),
  ),
);

class _Pending {
  final deleting = <String>{};
  bool pinning = false;
}

/// 写入锁属于账号，页面退出和查询刷新均不提前释放在途操作。
class DynamicsActions {
  DynamicsActions(this._repository, this._updates);
  final DynamicsRepository _repository;
  final DynamicsUpdates _updates;
  final _pending = HashMap<Account, _Pending>.identity();
  final _liking = HashMap<Account, Set<String>>.identity();

  Future<LoadingState<void>> remove(Account account, String id) =>
      _write(account, id, null);
  Future<LoadingState<void>> pin(Account account, String id, bool pinned) =>
      _write(account, id, pinned);

  Future<LoadingState<bool>>? toggleLike(
    Account account,
    DynamicItemModel item,
    bool displayedStatus,
  ) {
    if (!identical(account, Accounts.main)) return null;
    final id = item.idStr?.toString();
    if (id == null || id.isEmpty) {
      return Future.value(const Error('动态缺少 ID，请刷新后重试'));
    }
    final like = item.modules.moduleStat?.like;
    final status = like?.status ?? false;
    if (status != displayedStatus) {
      if (_liking[account]?.contains(id) == true) return null;
      return Future.value(Success(status));
    }
    final pending = setLike(account, id, !status);
    if (pending == null) return null;
    return _updateLike(pending, account, item, id, like, !status);
  }

  Future<LoadingState<void>>? setLike(Account account, String id, bool liked) {
    if (!identical(account, Accounts.main)) return null;
    final pending = _liking.putIfAbsent(account, () => {});
    if (!pending.add(id)) return null;
    return _writeLike(account, id, liked, pending);
  }

  Future<LoadingState<void>> _writeLike(
    Account account,
    String id,
    bool liked,
    Set<String> pending,
  ) async {
    try {
      return await _repository.like(account, id, liked);
    } catch (cause, stack) {
      return UnknownResult(cause: cause, stackTrace: stack);
    } finally {
      pending.remove(id);
      if (pending.isEmpty) _liking.remove(account);
    }
  }

  Future<LoadingState<bool>> _updateLike(
    Future<LoadingState<void>> pending,
    Account account,
    DynamicItemModel item,
    String id,
    DynamicStat? like,
    bool liked,
  ) async {
    final result = await pending;
    if (result is Error) return result;
    if (!result.isSuccess) return const UnknownResult();
    if (identical(account, Accounts.main) &&
        id == item.idStr?.toString() &&
        like != null &&
        identical(like, item.modules.moduleStat?.like)) {
      if (like.count case final count?) {
        like.count = max(0, count + (liked ? 1 : -1));
      }
      like.status = liked;
    }
    return Success(liked);
  }

  Future<LoadingState<void>> _write(
    Account account,
    String id,
    bool? pinned,
  ) async {
    if (!account.isLogin ||
        !identical(account, Accounts.main) ||
        (int.tryParse(id) ?? 0) <= 0) {
      return const Error('账号或动态已更新，请刷新');
    }
    final pending = _pending.putIfAbsent(account, _Pending.new);
    if (pending.pinning ||
        (pinned == null
            ? pending.deleting.contains(id)
            : pending.deleting.isNotEmpty)) {
      return const Error('正在处理动态，请稍候');
    }
    if (pinned == null) {
      pending.deleting.add(id);
    } else {
      pending.pinning = true;
    }
    try {
      final result = await (pinned == null
          ? _repository.remove(account, id)
          : _repository.pin(account, id, pinned));
      if (result.isSuccess) {
        if (pinned == null) {
          _updates.removed(account, id);
        } else {
          _updates.pinned(account, id, pinned);
        }
      }
      return result;
    } catch (cause, stack) {
      return UnknownResult(cause: cause, stackTrace: stack);
    } finally {
      if (pinned == null) {
        pending.deleting.remove(id);
      } else {
        pending.pinning = false;
      }
      if (!pending.pinning && pending.deleting.isEmpty) {
        _pending.remove(account);
      }
    }
  }
}
