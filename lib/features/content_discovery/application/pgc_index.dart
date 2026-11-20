import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/data/pgc_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/pgc/index_condition/data.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/pgc/index_result/list.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef PgcIndexQuery = ({int? indexType, String filters, Object owner});
final pgcConditionsProvider = FutureProvider.autoDispose
    .family<PgcIndexConditionData, int?>((ref, indexType) {
      final account = ref.watch(mainAccountProvider);
      return ref
          .watch(pgcRepositoryProvider)
          .indexConditions(account, indexType);
    }, retry: (_, _) => null);
final pgcResultsProvider = AsyncNotifierProvider.autoDispose
    .family<PgcResultsNotifier, PgcResultsState, PgcIndexQuery>(
      PgcResultsNotifier.new,
      retry: (_, _) => null,
    );

class PgcResultsState {
  PgcResultsState({
    required Iterable<PgcIndexItem> items,
    required this.nextPage,
    required this.hasMore,
    this.loadingMore = false,
    this.error,
    Object? source,
  }) : items = List.unmodifiable(items),
       source = source ?? Object();
  final List<PgcIndexItem> items;
  final int nextPage;
  final bool hasMore;
  final bool loadingMore;
  final String? error;
  final Object source;
  bool get canLoadMore => hasMore && !loadingMore && error == null;
  PgcResultsState operation({bool loadingMore = false, String? error}) =>
      PgcResultsState(
        items: items,
        nextPage: nextPage,
        hasMore: hasMore,
        loadingMore: loadingMore,
        error: error,
        source: source,
      );
}

class PgcResultsNotifier extends AsyncNotifier<PgcResultsState> {
  PgcResultsNotifier(this.query);
  final PgcIndexQuery query;
  @override
  Future<PgcResultsState> build() => _page(
    ref.watch(pgcRepositoryProvider),
    ref.watch(recommendAccountProvider),
    null,
  );
  Future<PgcResultsState> _page(
    PgcRepository repository,
    Account account,
    PgcResultsState? before,
  ) async {
    final page = before?.nextPage ?? 1;
    final data = await repository.indexResults(
      account,
      page: page,
      filters: Map<String, dynamic>.from(jsonDecode(query.filters) as Map),
      indexType: query.indexType,
    );
    final seen = <Object>{};
    final rows = data.list ?? <PgcIndexItem>[];
    final items = [
      for (final item in [...?before?.items, ...rows])
        if (seen.add(item.seasonId ?? item)) item,
    ];
    return PgcResultsState(
      items: items,
      nextPage: page + 1,
      hasMore:
          data.hasNext == 1 &&
          rows.isNotEmpty &&
          (before == null || items.length > before.items.length),
      source: before?.source,
    );
  }

  Future<void> loadMore({bool retry = false}) async {
    final before = state.value;
    if (state.isLoading ||
        state.hasError ||
        before == null ||
        !before.hasMore ||
        before.loadingMore ||
        (!retry && before.error != null)) {
      return;
    }
    final owner = ref;
    final account = owner.read(recommendAccountProvider);
    final repository = owner.read(pgcRepositoryProvider);
    bool current() =>
        owner.mounted &&
        identical(account, owner.read(recommendAccountProvider));
    state = AsyncData(before.operation(loadingMore: true));
    try {
      final result = await _page(repository, account, before);
      if (current()) {
        state = AsyncData(result);
      }
    } catch (_) {
      if (current()) {
        state = AsyncData(before.operation(error: '加载失败，点击重试'));
      }
    }
  }
}
