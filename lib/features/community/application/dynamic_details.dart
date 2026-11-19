import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final dynamicDetailsProvider = Provider(
  (ref) => DynamicDetails(ref.read(dynamicsRepositoryProvider)),
);

class DynamicDetails {
  DynamicDetails(this._repository);

  final DynamicsRepository _repository;
  final _pending = HashMap<Account, Set<Object>>.identity();

  Future<LoadingState<DynamicItemModel>> load(Account account, Object? id) =>
      _repository.detail(account, id);

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
