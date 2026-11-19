import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/data/recommendation_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
export 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart'
    show discoveryFilterProvider, cooperativeAuthorsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/application/recommendation_state.dart';
import 'package:pili_aurora_next/models/model_rec_video_item.dart';
import 'package:pili_aurora_next/features/content_discovery/application/cooperative_authors.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/features/content_discovery/application/media_author_filter.dart';

class _RecommendationQuery {
  _RecommendationQuery(this.context, this.account, this.app, this.saved);

  final Object? context;
  final Account account;
  final bool app;
  final List<BaseRcmdVideoItemModel> saved;
  final items = <BaseRcmdVideoItemModel>[];
  final seen = <Object>{};
  final pending = HashSet<Object>.identity();
  CancelToken cancel = CancelToken();
  final requests = <int, Future<LoadingState<List<BaseRcmdVideoItemModel>>>>{};
  Future<void>? preparation;
  Future<void>? running;
  TraceOperation? firstItems;
  TraceOperation? firstViewport;
  int? historyStart;
  String? error;
  int nextPage = 0,
      nextRequest = 0,
      batchSize = 10,
      emptyPages = 0,
      moreItems = 0;
  bool stopped = false;
}

final recommendationRepositoryProvider = Provider<RecommendationRepository>(
  (ref) => const RecommendationRepository(),
);
final recommendationFeedProvider =
    NotifierProvider.autoDispose<RecommendationFeed, RecommendationState>(
      RecommendationFeed.new,
    );

class RecommendationFeed extends Notifier<RecommendationState> {
  Account get queryAccount => ref.read(recommendAccountProvider);
  Account? _contextMain, _contextQuery;
  Object _context = Object();
  Object get queryContext {
    final main = ref.read(mainAccountProvider);
    final query = queryAccount;
    if (!identical(main, _contextMain) || !identical(query, _contextQuery)) {
      _contextMain = main;
      _contextQuery = query;
      _context = Object();
    }
    return _context;
  }

  bool get enableSaveLastData =>
      ref.read(recommendationPreferencesProvider).keepPrevious;
  bool get appRcmd => ref.read(recommendationPreferencesProvider).app;
  bool get savedRcmdTip =>
      ref.read(recommendationPreferencesProvider).showHistory;
  int? _historyStart;
  int? get lastRefreshAt => _historyStart;
  RecommendationState get snapshot => state;
  LoadingState<List<BaseRcmdVideoItemModel>> get loadingState => state.loading;

  void _emit([LoadingState<List<BaseRcmdVideoItemModel>>? loading]) {
    if (_disposed) return;
    state = RecommendationState(
      loading: loading ?? state.loading,
      historyStart: _historyStart,
      error: _query?.error,
      loadingMore: isLoading,
      stopped: isEnd,
      source: _query,
    );
  }

  @override
  RecommendationState build() {
    _disposed = false;
    _refreshScheduled = false;
    _query = null;
    _historyStart = null;
    // 角色通知更新查询归属，同时保留 Widget 提供的视口和后台标签状态。
    ref.listen(mainAccountProvider, (_, _) => _onAccountChanged());
    ref.listen(recommendAccountProvider, (_, _) => _onAccountChanged());
    ref.listen(recommendationPreferencesProvider, (previous, next) {
      if (previous?.app != next.app) {
        _onAccountChanged();
      } else {
        _historyStart = next.keepPrevious && next.showHistory
            ? _query?.historyStart
            : null;
        _emit();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _cardListeners.clear();
      if (_query case final query?) _invalidate(query);
    });
    return RecommendationState();
  }

  Future<void>? prepareQuery() => ref.read(discoveryFilterProvider).prepare();
  CooperativeAuthors get cooperativeAuthors =>
      ref.read(cooperativeAuthorsProvider);
  _RecommendationQuery? _query;
  final _cardListeners = HashMap<Object, Set<void Function()>>.identity();
  final _viewports = <Object, ({int itemCount, int columns, bool active})>{};
  bool _disposed = false, _active = true;
  int _viewportItems = 0, _columns = 1;

  int get viewportItems => _viewportItems;
  String? get loadMoreError => _query?.error;
  bool isPending(Object item) => _query?.pending.contains(item) ?? false;

  /// 监听可见卡片的揭示；卸载时移除空项，避免首页保活期间积累旧卡片引用。
  void Function() listenToCard(Object item, void Function() listener) {
    final listeners = _cardListeners.putIfAbsent(item, () => {})..add(listener);
    return () {
      listeners.remove(listener);
      if (listeners.isEmpty && identical(_cardListeners[item], listeners)) {
        _cardListeners.remove(item);
      }
    };
  }

  bool _current(_RecommendationQuery query) =>
      !_disposed &&
      identical(query, _query) &&
      identical(query.context, queryContext) &&
      query.app == appRcmd;

  int _target(_RecommendationQuery query) =>
      math.max(1, math.max(_viewportItems, query.moreItems));

  bool get isLoading => _query?.running != null;
  bool get isEnd => _query?.stopped ?? false;
  bool get canLoadMore => !isEnd && loadingState.dataOrNull != null;

  bool _refreshScheduled = false;
  void _onAccountChanged() {
    if (_query case final query? when !_current(query)) {
      _invalidate(query);
      _query = null;
      _historyStart = null;
      _emit(LoadingState.loading());
      if (_active && !_refreshScheduled) {
        // 共用凭据会依次发布主账号与推荐角色；同步撤销旧查询，合并本轮重读。
        _refreshScheduled = true;
        final owner = ref;
        scheduleMicrotask(() {
          if (!owner.mounted) return;
          _refreshScheduled = false;
          if (_active && _query == null) unawaited(onRefresh());
        });
      }
    }
  }

  void updateViewport({
    Object owner = const Object(),
    required int itemCount,
    required int columns,
    required bool active,
  }) {
    if (_disposed) return;
    _viewports[owner] = (
      itemCount: itemCount,
      columns: columns,
      active: active,
    );
    _selectViewport();
  }

  void removeViewport(Object owner) {
    if (!_disposed && _viewports.remove(owner) != null) {
      _selectViewport(deferWork: true);
    }
  }

  void _selectViewport({bool deferWork = false}) {
    final views = _viewports.values;
    final viewport =
        views.where((view) => view.active).firstOrNull ?? views.firstOrNull;
    if (viewport == null) {
      _active = false;
      return;
    }
    final (:itemCount, :columns, :active) = viewport;
    final changed = _viewportItems != itemCount || _active != active;
    _viewportItems = itemCount;
    _columns = columns;
    _active = active;
    if (!active) return;
    if (deferWork) {
      final owner = ref;
      scheduleMicrotask(() {
        if (owner.mounted && _active) _resumeViewport(changed);
      });
    } else {
      _resumeViewport(changed);
    }
  }

  void _resumeViewport(bool changed) {
    final query = _query;
    if (query == null || !_current(query)) {
      unawaited(onRefresh());
    } else if (changed && !query.stopped) {
      unawaited(_run(query));
    }
  }

  Future<LoadingState<List<BaseRcmdVideoItemModel>>> fetchRecommendations({
    required int index,
    required int pageSize,
    required CancelToken cancelToken,
    required Account account,
    required bool app,
  }) => ref
      .read(recommendationRepositoryProvider)
      .page(
        account: account,
        app: app,
        index: index,
        pageSize: pageSize,
        cancelToken: cancelToken,
      );

  List<BaseRcmdVideoItemModel> filterCandidates(
    Iterable<BaseRcmdVideoItemModel> source, {
    Iterable<BaseRcmdVideoItemModel> existing = const [],
  }) => ref
      .read(discoveryFilterProvider)
      .filter(
        source,
        existing: existing,
        deduplicate: true,
      );

  void _publish(_RecommendationQuery query) {
    if (!_current(query)) return;
    final data = List<BaseRcmdVideoItemModel>.of(query.items);
    _historyStart = enableSaveLastData && savedRcmdTip && query.saved.isNotEmpty
        ? query.historyStart
        : null;
    _emit(Success(List.unmodifiable(data)));
    _finishReadyTraces(query);
  }

  void _finishReadyTraces(_RecommendationQuery query) {
    // 首屏诊断结束后，不再为每张合作卡片扫描完整历史列表。
    if (query.firstItems == null && query.firstViewport == null) return;
    final data = query.items;
    final ready = data.where((item) => !query.pending.contains(item)).length;
    if (ready > 0) {
      query.firstItems?.finish(details: {'items': ready});
      query.firstItems = null;
    }
    if (query.firstViewport != null &&
        _viewportItems > 0 &&
        data.length >= _viewportItems &&
        data
            .take(_viewportItems)
            .every((item) => !query.pending.contains(item))) {
      query.firstViewport?.finish(
        details: {'items': ready, 'target': _viewportItems},
      );
      query.firstViewport = null;
    }
  }

  bool _needsAuthorCheck(BaseRcmdVideoItemModel item) =>
      ref.read(discoveryFilterProvider).needsAuthorCheck(item);

  Future<void> _checkAuthor(
    _RecommendationQuery query,
    BaseRcmdVideoItemModel item,
    void Function() onChecked,
  ) async {
    query.pending.add(item);
    await cooperativeAuthors.prepare(
      MediaAuthorFilter.videos(item).toList(),
      isCurrent: () => _current(query),
    );
    if (!_current(query)) return;
    query.pending.remove(item);
    final blocked = filterCandidates([item]).isEmpty;
    if (blocked) {
      _remove(query, item);
    }
    onChecked();
    if (blocked) {
      _publish(query);
    } else {
      // 列表成员和顺序未变，只揭示对应卡片，不复制列表或重建整个网格。
      _finishReadyTraces(query);
      for (final listener in _cardListeners[item]?.toList() ?? []) {
        listener();
      }
    }
    if (blocked && _active && !query.stopped) unawaited(_run(query));
  }

  void _settleBatch(
    _RecommendationQuery query,
    List<BaseRcmdVideoItemModel> added,
  ) {
    if (!_current(query)) return;
    query.emptyPages = added.any(query.items.contains)
        ? 0
        : query.emptyPages + 1;
    // 连续五页无有效增长后等待用户刷新，避免重复或全屏蔽来源持续请求。
    if (query.emptyPages >= 5) {
      query.stopped = true;
      _invalidate(query);
    }
    if (_active && !query.stopped) unawaited(_run(query));
  }

  void _accept(
    _RecommendationQuery query,
    List<BaseRcmdVideoItemModel> source,
  ) {
    final added = filterCandidates(source).where((item) {
      final key = MediaAuthorFilter.contentKey(item);
      return key == null || query.seen.add(key);
    }).toList();
    query.items.addAll(added);
    if (query.nextPage == 1) {
      final saved = filterCandidates(query.saved, existing: query.items);
      query.saved
        ..clear()
        ..addAll(saved);
      query.historyStart = query.items.length;
      query.items.addAll(saved);
      query.seen.addAll(
        saved.map(MediaAuthorFilter.contentKey).whereType<Object>(),
      );
    }
    final checking = [
      ...added,
      if (query.nextPage == 1) ...query.saved,
    ].where(_needsAuthorCheck).toList();
    var remaining = checking.length;
    void checked() {
      if (--remaining == 0) _settleBatch(query, added);
    }

    for (final item in checking) {
      unawaited(_checkAuthor(query, item, checked));
    }
    _publish(query);
    if (checking.isEmpty) _settleBatch(query, added);
  }

  void _finishTrace(_RecommendationQuery query) {
    query.firstItems?.finish(details: {'interrupted': true});
    query.firstViewport?.finish(details: {'interrupted': true});
    query.firstItems = query.firstViewport = null;
  }

  void _invalidate(_RecommendationQuery query) {
    query.cancel.cancel('recommendations invalidated');
    query.requests.clear();
    _finishTrace(query);
  }

  void _startRequests(_RecommendationQuery query) {
    // App 的 idx/pull 顺序推进；Web 首包后最多下载两页并按索引合并。
    final limit = query.app || query.nextPage == 0 ? 1 : 2;
    while (query.requests.length < limit &&
        (query.nextRequest == 0 ||
            query.items.length + query.requests.length * query.batchSize <
                _target(query))) {
      final index = query.nextRequest++;
      query.requests[index] = () async {
        try {
          return await fetchRecommendations(
            index: index,
            pageSize: math.min(
              50,
              math.max(20, _target(query) - query.items.length),
            ),
            cancelToken: query.cancel,
            account: query.account,
            app: query.app,
          );
        } catch (_) {
          return const Error('推荐加载失败，请重试');
        }
      }();
    }
  }

  Future<void> _runLoop(_RecommendationQuery query) async {
    try {
      while (_current(query) &&
          _active &&
          !query.stopped &&
          (query.nextPage == 0 ||
              query.requests.isNotEmpty ||
              query.items.length < _target(query))) {
        _startRequests(query);
        if (query.requests.isEmpty) return;
        // 下载不等待卡片作者检查，响应仍按请求索引提交。
        final result = await query.requests[query.nextPage]!;
        if (!_current(query)) return;
        await query.preparation;
        if (!_current(query) || query.stopped) return;
        query.requests.remove(query.nextPage);
        switch (result) {
          case Success(:final response):
            ++query.nextPage;
            if (response.isNotEmpty) query.batchSize = response.length;
            _accept(query, response);
          case Error():
            query
              ..stopped = true
              ..error = result.errMsg ?? '推荐加载失败，请重试';
            if (loadingState.dataOrNull?.isNotEmpty != true) {
              _emit(result);
            } else {
              _emit();
            }
          case Loading():
            query.stopped = true;
        }
      }
    } catch (_) {
      if (_current(query)) {
        query
          ..stopped = true
          ..error = '推荐加载失败，请重试';
        if (loadingState.dataOrNull?.isNotEmpty != true) {
          _emit(const Error('推荐加载失败，请重试'));
        } else {
          _emit();
        }
      }
    } finally {
      if (!_current(query) || query.stopped) _invalidate(query);
    }
  }

  Future<void> _run(_RecommendationQuery query) {
    if (query.running case final running?) return running;
    if (query.nextPage > 0 &&
        query.requests.isEmpty &&
        query.items.length >= _target(query)) {
      return Future.value();
    }
    final running = _runLoop(query).whenComplete(() {
      query.running = null;
      if (_current(query)) _emit();
    });
    query.running = running;
    _emit();
    return running;
  }

  Future<void> onRefresh() {
    if (_disposed) return Future.value();
    final previous = _query;
    final sameContext = previous == null || _current(previous);
    final previousItems = sameContext ? loadingState.dataOrNull : null;
    final visible = previousItems?.where((item) => !isPending(item)).toList();
    final visibleHistoryStart = _historyStart == null
        ? null
        : previousItems
              ?.take(_historyStart!)
              .where((item) => !isPending(item))
              .length;
    final old = enableSaveLastData && visible != null
        ? visible
        : <BaseRcmdVideoItemModel>[];
    if (previous != null) _invalidate(previous);
    final query = _RecommendationQuery(
      queryContext,
      queryAccount,
      appRcmd,
      old.length > 200 ? old.take(50).toList() : old,
    );
    _query = query;
    // 保留提示卡与旧内容的相对位置，直到首包发布时一并替换。
    _historyStart = visibleHistoryStart;
    if (!sameContext) {
      _emit(LoadingState.loading());
    } else if (visible != null) {
      // 未完成作者检查的骨架随刷新撤下，避免切换查询后提前揭示。
      _emit(Success(List.unmodifiable(visible)));
    }
    query
      ..firstItems = Diagnostics.instance.begin('recommendFirstItems', 'ready')
      ..firstViewport = Diagnostics.instance.begin(
        'recommendViewport',
        'ready',
      )
      // 同步与下载同时开始，发布前等待屏蔽准备完成。
      ..preparation = prepareQuery();
    return _run(query);
  }

  Future<void> onReload() {
    _emit(LoadingState.loading());
    return onRefresh();
  }

  Future<void> onLoadMore() {
    final query = _query;
    if (query == null || !_current(query)) return onRefresh();
    if (query.stopped || !_active) return Future.value();
    if (query.running case final running?) return running;
    query.moreItems =
        query.items.length + math.max(_columns * 2, query.batchSize);
    return _run(query);
  }

  Future<void> retryLoadMore() {
    final query = _query;
    if (query == null || !_current(query)) return onRefresh();
    query
      ..stopped = false
      ..error = null
      ..cancel = CancelToken()
      ..nextRequest = query.nextPage;
    _emit();
    return _run(query);
  }

  void _remove(_RecommendationQuery query, BaseRcmdVideoItemModel item) {
    final index = query.items.indexOf(item);
    if (index < 0) return;
    query.items.removeAt(index);
    query.saved.remove(item);
    if (query.historyStart case final start? when index < start) {
      query.historyStart = start - 1;
    }
  }

  void removeRecommendation(BaseRcmdVideoItemModel item) {
    final query = _query;
    if (query == null || !_current(query)) return;
    if (query.nextPage == 0) {
      final visible = List<BaseRcmdVideoItemModel>.of(
        loadingState.dataOrNull ?? [],
      );
      final index = visible.indexOf(item);
      query.saved.remove(item);
      final key = MediaAuthorFilter.contentKey(item);
      if (key != null) query.seen.add(key);
      if (index >= 0) {
        visible.removeAt(index);
        if (_historyStart case final start? when index < start) {
          _historyStart = start - 1;
        }
      }
      _emit(Success(List.unmodifiable(visible)));
      return;
    }
    _remove(query, item);
    _publish(query);
    if (_active && !query.stopped) unawaited(_run(query));
  }
}

final recommendationCardPendingProvider = NotifierProvider.autoDispose
    .family<RecommendationCardPending, bool, Object>(
      RecommendationCardPending.new,
    );

class RecommendationCardPending extends Notifier<bool> {
  RecommendationCardPending(this.item);
  final Object item;
  @override
  bool build() {
    // 结构变更时重新核对；异步揭示只通知这一张卡片。
    ref.watch(recommendationFeedProvider.select((value) => value.loading));
    final feed = ref.read(recommendationFeedProvider.notifier);
    ref.onDispose(feed.listenToCard(item, () => state = feed.isPending(item)));
    return feed.isPending(item);
  }
}
