import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_pgc/list.dart';
import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/pgc.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_result/list.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_timeline/result.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final pgcRepositoryProvider = Provider((ref) => const PgcRepository());

class PgcRepository {
  const PgcRepository();
  Future<LoadingState<DiscoveryPage<PgcIndexItem, void>>> catalog(
    Account account,
    int page,
    bool cinema,
  ) async => switch (await PgcHttp.pgcIndex(
    account: account,
    page: page,
    indexType: cinema ? 102 : null,
  )) {
    Success(:final response) => Success(
      DiscoveryPage(response ?? [], metadata: null),
    ),
    Error error => error,
    _ => LoadingState.loading(),
  };

  Future<LoadingState<DiscoveryPage<FavPgcItemModel, int>>> follows(
    Account account,
    int page,
    bool cinema,
  ) async {
    if (!account.isLogin) {
      return const Success(DiscoveryPage([], metadata: 0, hasMore: false));
    }
    return switch (await FavHttp.favPgc(
      account: account,
      pn: page,
      type: cinema ? 2 : 1,
    )) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.list ?? [],
          metadata: response.total ?? -1,
          total: response.total,
        ),
      ),
      Error error => error,
      _ => LoadingState.loading(),
    };
  }

  Future<LoadingState<DiscoveryPage<TimelineResult, String?>>> timeline(
    Account account,
  ) async {
    final results = await Future.wait([
      PgcHttp.pgcTimeline(types: 1, before: 6, after: 6, account: account),
      PgcHttp.pgcTimeline(types: 4, before: 6, after: 6, account: account),
    ]);
    final days = <Object, TimelineResult>{};
    Error? failure;
    for (final result in results) {
      if (result case Error error) {
        failure ??= error;
        continue;
      }
      for (final day in result.dataOrNull ?? <TimelineResult>[]) {
        final key = day.dateTs ?? day.date ?? day;
        final existing = days[key];
        if (existing == null) {
          days[key] = TimelineResult(
            date: day.date,
            dateTs: day.dateTs,
            dayOfWeek: day.dayOfWeek,
            isToday: day.isToday,
            episodes: List.of(day.episodes ?? []),
          );
        } else {
          existing.episodes!.addAll(day.episodes ?? []);
        }
      }
    }
    if (days.isEmpty && failure != null) return failure;
    return Success(
      DiscoveryPage(
        days.values.toList()
          ..sort((a, b) => (a.dateTs ?? 0).compareTo(b.dateTs ?? 0)),
        metadata: failure == null ? null : '部分时间表加载失败，点击重试',
        hasMore: false,
      ),
    );
  }
}
