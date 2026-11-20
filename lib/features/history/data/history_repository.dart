import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/history/domain/data.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

class HistoryRepository {
  Future<HistoryData> page(
    Account account, {
    required String type,
    required String keyword,
    required bool search,
    Object? cursor,
  }) async =>
      (await (search
              ? UserHttp.searchHistory(
                  account: account,
                  pn: cursor as int? ?? 1,
                  keyword: keyword,
                )
              : UserHttp.historyList(
                  account: account,
                  type: type,
                  max: (cursor as (int, int)?)?.$1,
                  viewAt: cursor?.$2,
                )))
          .data;
  Future<LoadingState<void>> remove(Account account, List<String> ids) =>
      UserHttp.delHistory(ids.join(','), account: account);
  Future<LoadingState<void>> clear(Account account) =>
      UserHttp.clearHistory(account: account);
  Future<LoadingState<void>> pause(Account account, bool paused) =>
      UserHttp.pauseHistory(paused, account: account);
  Future<LoadingState<bool>> status(Account account) =>
      UserHttp.historyStatus(account: account);
  Future<void> cachePause(bool paused) =>
      GStorage.localCache.put(LocalCacheKey.historyPause, paused);
}
