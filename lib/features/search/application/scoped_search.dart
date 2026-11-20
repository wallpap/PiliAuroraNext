import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/search/data/scoped_search_repository.dart';
import 'package:pili_aurora_next/features/search/domain/scoped_search.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

export 'package:pili_aurora_next/features/search/domain/scoped_search.dart';

typedef ScopedSearchQuery = ({
  ScopedSearchKind kind,
  String keyword,
  int? mid,
  Object owner,
});
final scopedSearchProvider =
    AsyncNotifierProvider.family<
      ScopedSearchNotifier,
      ScopedSearchState,
      ScopedSearchQuery
    >(ScopedSearchNotifier.new, isAutoDispose: true, retry: (_, _) => null);

class ScopedSearchState {
  ScopedSearchState({
    required Iterable<dynamic> items,
    required this.nextPage,
    required this.hasMore,
    this.total,
    this.offset,
    Object? source,
    this.loadingMore = false,
    this.error,
    this.emptyPages = 0,
  }) : items = List.unmodifiable(items),
       source = source ?? Object();
  final int emptyPages;
  final List<dynamic> items;
  final int nextPage;
  final bool hasMore;
  final int? total;
  final String? offset;
  final Object source;
  final bool loadingMore;
  final String? error;
  bool get canLoadMore => hasMore && !loadingMore && error == null;
  ScopedSearchState operation({bool loadingMore = false, String? error}) =>
      ScopedSearchState(
        items: items,
        nextPage: nextPage,
        hasMore: hasMore,
        total: total,
        offset: offset,
        source: source,
        loadingMore: loadingMore,
        error: error,
        emptyPages: emptyPages,
      );
}

class ScopedSearchNotifier extends AsyncNotifier<ScopedSearchState> {
  ScopedSearchNotifier(this.query);
  final ScopedSearchQuery query;
  bool get live =>
      query.kind == ScopedSearchKind.room ||
      query.kind == ScopedSearchKind.user;
  @override
  Future<ScopedSearchState> build() {
    final account = ref.watch(
      live ? recommendAccountProvider : mainAccountProvider,
    );
    return _page(account, null);
  }

  Future<ScopedSearchState> _page(
    Account account,
    ScopedSearchState? before,
  ) async {
    final page = before?.nextPage ?? 1;
    if (query.keyword.trim().isEmpty) {
      return ScopedSearchState(items: [], nextPage: 1, hasMore: false);
    }
    final result = await const ScopedSearchRepository().page(
      account: account,
      kind: query.kind,
      keyword: query.keyword,
      page: page,
      mid: query.mid,
      offset: before?.offset,
    );
    Object identity(dynamic row) => switch (query.kind) {
      ScopedSearchKind.room => row.roomid ?? row,
      ScopedSearchKind.user => row.roomid ?? row,
      ScopedSearchKind.archive => (row as ScopedSearchArchive).aid,
      ScopedSearchKind.dynamic => row.idStr ?? row,
    };
    final seen = <Object?>{};
    final items = [
      for (final row in [...?before?.items, ...result.rows])
        if (seen.add(identity(row))) row,
    ];
    final more =
        result.hasMore &&
        (before == null ||
            items.length > before.items.length ||
            query.kind == ScopedSearchKind.dynamic);
    final emptyPages = items.length == (before?.items.length ?? 0)
        ? (before?.emptyPages ?? 0) + 1
        : 0;
    return ScopedSearchState(
      emptyPages: emptyPages,
      items: items,
      total: result.total ?? before?.total,
      nextPage: page + 1,
      offset: result.offset,
      hasMore: more && emptyPages < 5,
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
    final accountProvider = live
        ? recommendAccountProvider
        : mainAccountProvider;
    final account = owner.read(accountProvider);
    bool current() =>
        owner.mounted && identical(account, owner.read(accountProvider));
    state = AsyncData(before.operation(loadingMore: true));
    try {
      final result = await _page(account, before);
      if (current()) state = AsyncData(result);
    } catch (_) {
      if (current()) {
        state = AsyncData(before.operation(error: '加载失败，点击重试'));
      }
    }
  }
}
