import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final rankRepositoryProvider = Provider((ref) => const RankRepository());

class RankRepository {
  const RankRepository();
  Future<LoadingState<DiscoveryPage<Object, void>>> fetch(
    Account account, {
    int? rid,
    int? seasonType,
  }) async {
    final LoadingState<List<Object>?> result = rid != null
        ? await VideoHttp.getRankVideoList(rid, account: account)
        : seasonType == 1
        ? await VideoHttp.pgcRankList(seasonType: seasonType!, account: account)
        : await VideoHttp.pgcSeasonRankList(
            seasonType: seasonType!,
            account: account,
          );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(response ?? [], metadata: null, hasMore: false),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }
}
