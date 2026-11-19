import 'package:pili_aurora_next/http/black.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

typedef BlockedAuthorPage = ({List<int?> mids, int? total});

class BlockedAuthorRepository {
  const BlockedAuthorRepository();

  Future<BlockedAuthorPage?> load(Account account, int page) async {
    final result = await BlackHttp.blackList(pn: page, account: account);
    return switch (result) {
      Success(:final response) => (
        mids: response.list?.map((entry) => entry.mid).toList() ?? const [],
        total: response.total,
      ),
      _ => null,
    };
  }

  Map<dynamic, dynamic> get _saved =>
      switch (GStorage.localCache.get(LocalCacheKey.blackMidsByAccount)) {
        final Map entries => entries,
        _ => const {},
      };

  Set<int> read(int uid) => switch (_saved['$uid']) {
    final Iterable mids => mids.whereType<int>().toSet(),
    _ => {},
  };

  Future<void> save(int uid, Set<int> mids) => GStorage.localCache.put(
    LocalCacheKey.blackMidsByAccount,
    {..._saved, '$uid': mids.toList()},
  );
}
