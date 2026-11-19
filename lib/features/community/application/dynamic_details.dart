import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/features/member_space/application/member_moderation.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/models/remote/dynamic/dyn_reserve/data.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

final dynamicDetailsProvider = Provider(
  (ref) => DynamicDetails(ref.read(dynamicsRepositoryProvider)),
);

class DynamicDetails {
  DynamicDetails(this._repository);

  static final legacy = DynamicDetails(const DynamicsRepository());
  static bool get checkAfterPublish => Pref.enableCreateDynAntifraud;

  final DynamicsRepository _repository;
  final _pending = HashMap<Account, Set<Object>>.identity();

  Future<LoadingState<DynamicItemModel>> load(Account account, Object? id) =>
      _repository.detail(account: account, id: id);

  Future<LoadingState<List<OpusPicModel>?>> pictures(Object? id) =>
      _repository.pictures(id);

  Future<LoadingState<DynReserveData>?> reserve(
    Account account,
    Object id,
    Reserve reservation,
  ) => _write(
    account,
    ('reserve', reservation.rid),
    () => _repository.reserve(account, id, reservation),
  );

  Future<LoadingState<Object?>> report(
    Account account, {
    required int author,
    required Object id,
    required int reason,
    required String? description,
    required bool block,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return const Error('账号或动态已变更，请重新打开举报页面');
    final moderation = MemberModeration.capture(account);
    final result = await _write(
      account,
      ('report', id.toString()),
      () => _repository.report(account, author, id, reason, description),
    );
    if (result == null) return const Error('账号已切换或正在举报');
    if (!result.isSuccess || !block || !isCurrent()) return result;
    final blocked = await moderation.block(author);
    return blocked is Error ? Success('举报成功；拉黑用户：$blocked') : result;
  }

  Future<LoadingState<DynamicItemModel>> resolve({
    String? id,
    Object? replyId,
  }) => _repository.detail(id: id, replyId: replyId);

  Future<LoadingState<bool>> checkPublicVisibility(Object id) async {
    final result = await _repository.detail(id: id, anonymous: true);
    return switch (result) {
      Success(:final response) => Success(response.visible != false),
      Error error => error,
      Loading loading => loading,
    };
  }

  Future<LoadingState<void>?> setVisibility(
    Account account,
    Object id,
    bool makePublic,
  ) => _write(
    account,
    id.toString(),
    () => _repository.setVisibility(account, id, makePublic),
  );

  Future<LoadingState<String?>?> setReplySubject(
    Account account,
    int oid,
    int type,
    int action,
  ) => _write(
    account,
    (oid, type),
    () => _repository.setReplySubject(account, oid, type, action),
  );

  Future<LoadingState<T>?> _write<T>(
    Account account,
    Object target,
    Future<LoadingState<T>> Function() write,
  ) async {
    if (!identical(account, Accounts.main)) return null;
    final pending = _pending.putIfAbsent(account, () => {});
    if (!pending.add(target)) return null;
    try {
      return await write();
    } catch (cause, stack) {
      return UnknownResult(cause: cause, stackTrace: stack);
    } finally {
      pending.remove(target);
      if (pending.isEmpty) _pending.remove(account);
    }
  }
}
