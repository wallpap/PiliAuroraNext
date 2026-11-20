import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/cooperative_authors.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/application/media_author_filter.dart';
import 'package:pili_aurora_next/features/search/data/search_repository.dart';
import 'package:pili_aurora_next/features/search/application/search_verification_failure.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/search/domain/filters/search_type.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/features/search/domain/result.dart';
import 'package:pili_aurora_next/features/search/domain/search_esports.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

export 'package:pili_aurora_next/features/search/application/search_verification_failure.dart';

typedef SearchResultsQuery = ({
  String keyword,
  SearchType type,
  Object owner,
  String filters,
  Object revision,
});
final searchResultsProvider = AsyncNotifierProvider.autoDispose
    .family<SearchResultsNotifier, SearchResultsState, SearchResultsQuery>(
      SearchResultsNotifier.new,
      retry: (_, _) => null,
    );

class SearchResultsState {
  SearchResultsState({
    required Iterable<dynamic> items,
    required this.nextPage,
    required this.hasMore,
    this.total,
    this.loadingMore = false,
    this.error,
    this.emptyPages = 0,
    this.firstAid,
    Iterable<Object> pendingItems = const [],
    Iterable<SearchUser> users = const [],
    Iterable<SearchPgcItemModel> media = const [],
    Iterable<SearchActivity> activities = const [],
    this.esports,
    Object? source,
  }) : items = List.unmodifiable(items),
       pendingItems = Set.unmodifiable(pendingItems),
       users = List.unmodifiable(users),
       media = List.unmodifiable(media),
       activities = List.unmodifiable(activities),
       source = source ?? Object();
  final List<dynamic> items;
  final Set<Object> pendingItems;
  final List<SearchUser> users;
  final List<SearchPgcItemModel> media;
  final List<SearchActivity> activities;
  final SearchEsports? esports;
  final int? firstAid;
  final int nextPage;
  final int? total;
  final bool hasMore;
  final int emptyPages;
  final bool loadingMore;
  final Object? error;
  final Object source;
  bool get canLoadMore => hasMore && !loadingMore && error == null;
  SearchResultsState operation({
    bool loadingMore = false,
    Object? error,
    Iterable<dynamic>? items,
  }) => SearchResultsState(
    items: items ?? this.items,
    pendingItems: pendingItems,
    nextPage: nextPage,
    hasMore: hasMore,
    total: total,
    users: users,
    media: media,
    activities: activities,
    esports: esports,
    firstAid: firstAid,
    source: source,
    loadingMore: loadingMore,
    error: error,
    emptyPages: emptyPages,
  );
}

class SearchResultsNotifier extends AsyncNotifier<SearchResultsState> {
  SearchResultsNotifier(this.query);
  final SearchResultsQuery query;
  String? _token;
  Set<Object> _hidden = {};
  @override
  Future<SearchResultsState> build() {
    final account = ref.watch(recommendAccountProvider);
    final main = ref.watch(mainAccountProvider);
    _token = null;
    _hidden = {};
    final initial = Completer<SearchResultsState>();
    unawaited(_readPages(ref, account, main, null, initial: initial));
    return initial.future;
  }

  bool _current(Ref owner, Account account, Account main) =>
      owner.mounted &&
      identical(account, owner.read(recommendAccountProvider)) &&
      identical(main, owner.read(mainAccountProvider));
  Object _identity(dynamic item) => item is SearchPgcItemModel
      ? ('pgc', item.seasonId ?? item.mediaId ?? item)
      : MediaAuthorFilter.contentKey(item) ?? item as Object;
  Future<SearchResultsState> _page(
    Ref owner,
    Account account,
    Account main,
    SearchResultsState? before,
    void Function(SearchResultsState) publish,
  ) async {
    final hidden = _hidden;
    final filters = Map<String, dynamic>.from(jsonDecode(query.filters) as Map);
    const authorFilter = DiscoveryFilter();
    final filtering = authorFilter.enabled;
    final includeCoauthors = authorFilter.includeCoauthors;
    final blacklist = authorFilter.prepare();
    var page = before?.nextPage ?? 1;
    var emptyPages = before?.emptyPages ?? 0;
    var more = false;
    var total = before?.total;
    var firstAid = before?.firstAid;
    var users = before?.users ?? <SearchUser>[];
    var media = before?.media ?? <SearchPgcItemModel>[];
    var activities = before?.activities ?? <SearchActivity>[];
    var esports = before?.esports;
    final source = before?.source ?? Object();
    final items = <dynamic>[...?before?.items];
    final pending = <CooperativeVideo, Object>{};
    final seen = <Object>{
      for (final item in items) _identity(item),
    };
    final startLength = items.length;
    bool isCurrent() => _current(owner, account, main);
    bool isBlocked(Object? item) =>
        filtering &&
        authorFilter.blocks(item, checkCoauthors: includeCoauthors);
    SearchResultsState snapshot({bool loadingMore = false}) =>
        SearchResultsState(
          items: items.where((item) => !hidden.contains(_identity(item))),
          pendingItems: pending.values,
          total: total,
          nextPage: page,
          hasMore: more,
          firstAid: firstAid,
          users: users,
          media: media,
          activities: activities,
          esports: esports,
          source: source,
          emptyPages: emptyPages,
          loadingMore: loadingMore,
        );
    for (var attempt = 0; attempt < 5; attempt++) {
      final type =
          query.type == SearchType.all &&
              (page > 1 || filters['filtered'] == true)
          ? SearchType.video
          : query.type;
      final result = await const SearchRepository().results(
        account: account,
        type: type,
        keyword: query.keyword,
        page: page,
        filters: filters,
        verificationToken: _token,
      );
      if (attempt == 0 && blacklist != null) await blacklist;
      if (!isCurrent()) throw const Error('查询已更新');
      final data = result.data;
      final rows = data.list ?? <dynamic>[];
      if (page == 1) {
        total = data.numResults;
        if (data is SearchVideoData) {
          firstAid = data.list?.firstOrNull?.aid;
          users = (data.searchUser ?? [])
              .where((e) => !filtering || !authorFilter.contains(e.mid))
              .toList();
          media = data.searchMedia ?? [];
          activities = data.searchActivity ?? [];
          esports = data.searchEsports;
        }
      }
      final oldLength = items.length;
      for (final item in rows) {
        if (isBlocked(item)) continue;
        final key = _identity(item);
        if (hidden.contains(key) || !seen.add(key)) continue;
        items.add(item);
        if (authorFilter.authorsToCheck(item).firstOrNull case final video?) {
          pending[video] = item as Object;
        }
      }
      more =
          rows.isNotEmpty &&
          (total == null ? rows.length >= 20 : page * 20 < total);
      page++;
      if (pending.isNotEmpty) {
        publish(snapshot(loadingMore: true));
        await CooperativeAuthors.shared.prepare(
          pending.keys.toList(),
          isCurrent: isCurrent,
          onChecked: (video) {
            final item = pending.remove(video)!;
            if (isBlocked(item)) {
              items.remove(item);
              seen.remove(_identity(item));
            }
            if (pending.isNotEmpty) publish(snapshot(loadingMore: true));
          },
        );
        if (!isCurrent()) throw const Error('查询已更新');
      }
      emptyPages = items.length == oldLength ? emptyPages + 1 : 0;
      more = more && emptyPages < 5 && (filtering || items.length > oldLength);
      if (!more ||
          !filtering ||
          items.length - startLength >= 20 ||
          attempt == 4) {
        break;
      }
      publish(snapshot(loadingMore: true));
    }
    return snapshot();
  }

  Future<void> _readPages(
    Ref owner,
    Account account,
    Account main,
    SearchResultsState? before, {
    Completer<SearchResultsState>? initial,
  }) async {
    if (initial == null) {
      state = before == null
          ? const AsyncLoading()
          : AsyncData(before.operation(loadingMore: true));
    }
    var latest = before;
    void publish(SearchResultsState snapshot) {
      latest = snapshot;
      if (initial != null && !initial.isCompleted) {
        initial.complete(snapshot);
      } else if (_current(owner, account, main)) {
        state = AsyncData(snapshot);
      }
    }

    try {
      publish(await _page(owner, account, main, before, publish));
    } catch (error, stack) {
      if (initial != null && !initial.isCompleted) {
        initial.completeError(error, stack);
      } else if (_current(owner, account, main)) {
        state = latest == null
            ? AsyncError(error, stack)
            : AsyncData(state.requireValue.operation(error: error));
      }
    }
  }

  Future<void> verify(
    SearchVerificationRequired challenge,
    String token,
  ) async {
    final before = !state.isLoading && !state.hasError ? state.value : null;
    if (state.isLoading ||
        !identical(state.error ?? before?.error, challenge)) {
      return;
    }
    final owner = ref;
    final account = owner.read(recommendAccountProvider);
    final main = owner.read(mainAccountProvider);
    if (!_current(owner, account, main)) return;
    _token = token;
    await _readPages(owner, account, main, before);
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
    final main = owner.read(mainAccountProvider);
    if (!_current(owner, account, main)) return;
    await _readPages(owner, account, main, before);
  }

  void remove(Object item) {
    if (!_current(
      ref,
      ref.read(recommendAccountProvider),
      ref.read(mainAccountProvider),
    )) {
      return;
    }
    final data = state.value;
    if (state.isLoading || state.hasError || data == null) return;
    _hidden.add(_identity(item));
    state = AsyncData(
      data.operation(
        items: data.items.where((e) => !identical(e, item)),
        loadingMore: data.loadingMore,
        error: data.error,
      ),
    );
  }
}
