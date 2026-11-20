import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/blocked_author.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

const blockedAuthorPageSize = 50;

class BlockedAuthorRepository {
  const BlockedAuthorRepository();

  Future<LoadingState<BlockedAuthorPage>> load(Account account, int page) =>
      Request().requestApi(
        Api.blackLst,
        kind: ApiCallKind.query,
        decode: (body) {
          final data = body['data'] as Map<String, dynamic>;
          final entries = data['list'] as List<dynamic>? ?? const [];
          return (
            items: [for (final entry in entries) _decodeAuthor(entry)],
            total: data['total'] as int?,
          );
        },
        queryParameters: {
          'pn': page,
          'ps': blockedAuthorPageSize,
          're_version': 0,
          'jsonp': 'jsonp',
          'csrf': account.csrf,
        },
        options: Options(extra: {'account': account}),
      );

  BlockedAuthor _decodeAuthor(Map<String, dynamic> data) => BlockedAuthor(
    mid: data['mid'] as int?,
    mtime: data['mtime'] as int?,
    uname: data['uname'] as String?,
    face: data['face'] as String?,
  );

  Future<LoadingState<void>> remove(Account account, int mid) =>
      VideoHttp.relationMod(account: account, mid: mid, act: 6, reSrc: 11);

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
