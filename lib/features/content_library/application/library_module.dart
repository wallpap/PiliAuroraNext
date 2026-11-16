import 'dart:async';
import 'dart:collection';

import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

/// 仅发布成功写入的失效信号，不保存另一份列表。历史入口与 Riverpod 共用此 Seam。
abstract class LibraryModule {
  final _changes = StreamController<Account>.broadcast(sync: true);
  final _writing = HashSet<Account>.identity();
  Stream<Account> get changes => _changes.stream;
  bool owns(Account account);

  Future<LoadingState<T>> write<T>(
    Account account,
    Future<LoadingState<T>> Function() send,
  ) async {
    if (!owns(account) || !account.isLogin) return const Error('账号已切换或未登录');
    // Account 的值相等语义不能合并同 UID 的新凭据。
    if (_writing.any((item) => identical(item, account))) {
      return const Error('操作进行中');
    }
    _writing.add(account);
    try {
      final result = await send();
      if (result.isSuccess && owns(account) && !_changes.isClosed) {
        _changes.add(account);
      }
      return result;
    } catch (error, stack) {
      return UnknownResult(cause: error, stackTrace: stack);
    } finally {
      _writing.remove(account);
    }
  }

  Future<void> close() => _changes.close();
}
