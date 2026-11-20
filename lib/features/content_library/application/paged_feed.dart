import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

/// 分页交付下一游标；null 表示结束，不从过滤后的数量推算远端页码。
class FeedPage<T, M> {
  FeedPage(Iterable<T> items, {required this.metadata, this.next})
    : items = List.unmodifiable(items);
  final List<T> items;
  final M metadata;
  final Object? next;
}

class FeedState<T, M> {
  FeedState({
    required Iterable<T> items,
    required M metadata,
    required Account account,
    required Object source,
    Object? next,
    Error? error,
  }) : this._(
         items: List.unmodifiable(items),
         metadata: metadata,
         account: account,
         source: source,
         next: next,
         error: error,
       );

  FeedState._({
    required this.items,
    required this.metadata,
    required this.account,
    required this.source,
    this.next,
    this.loadingMore = false,
    this.error,
  });
  final List<T> items;
  final M metadata;
  final Account account;
  final Object source;
  final Object? next;
  final bool loadingMore;
  final Error? error;
  bool get canLoadMore => next != null && !loadingMore && error == null;
  FeedState<T, M> operation({bool loadingMore = false, Error? error}) =>
      FeedState._(
        items: items,
        metadata: metadata,
        account: account,
        source: source,
        next: next,
        loadingMore: loadingMore,
        error: error,
      );
}

/// 查询、刷新和分页共用同一 Interface；派生 Module 只负责领域页协议。
abstract class PagedFeed<T, M> extends AsyncNotifier<FeedState<T, M>> {
  Account watchAccount();
  bool ownsAccount(Account account);
  Object itemKey(T item);
  Future<FeedPage<T, M>> fetch(Account account, Object? cursor);
  M mergeMetadata(M previous, M next) => next;
  bool get requiresLogin => true;

  /// 需要用户显式继续扫描的领域可保留游标，页面同时关闭空页自动分页。
  bool get endOnEmptyBudget => true;
  Object _generation = Object();

  /// 刷新与失败期间可展示同账号快照；写入和分页仍须通过 isCurrent。
  FeedState<T, M>? get displayState {
    final snapshot = state.value;
    return snapshot != null &&
            !state.isReloading &&
            ownsAccount(snapshot.account)
        ? snapshot
        : null;
  }

  @override
  Future<FeedState<T, M>> build() async {
    _generation = Object();
    final source = _generation;
    final account = watchAccount();
    if (requiresLogin && !account.isLogin) throw const Error('账号未登录');
    final owner = ref;
    var page = await fetch(account, null);
    final cursors = <Object>{};
    // 隐藏内容可能使首屏为空，仍按远端游标补位，并限制连续空页。
    for (var budget = 0; page.items.isEmpty && page.next != null; budget++) {
      if (!owner.mounted ||
          !identical(source, _generation) ||
          !ownsAccount(account)) {
        throw const Error('账号或查询已更新');
      }
      if (budget == 4) {
        if (endOnEmptyBudget) {
          page = FeedPage(page.items, metadata: page.metadata);
        }
        break;
      }
      if (!cursors.add(page.next!)) {
        page = FeedPage(page.items, metadata: page.metadata);
        break;
      }
      final next = await fetch(account, page.next);
      page = FeedPage(
        next.items,
        metadata: mergeMetadata(page.metadata, next.metadata),
        next: next.next,
      );
    }
    final seen = <Object>{};
    return FeedState(
      items: page.items.where((item) => seen.add(itemKey(item))),
      metadata: page.metadata,
      account: account,
      source: source,
      next: page.next,
      error: !endOnEmptyBudget && page.items.isEmpty && page.next != null
          ? const Error('连续五页没有可显示内容，请继续加载')
          : null,
    );
  }

  bool isCurrent(FeedState<T, M> snapshot) =>
      ref.mounted &&
      !state.isLoading &&
      !state.hasError &&
      identical(snapshot.source, state.value?.source) &&
      ownsAccount(snapshot.account);

  Future<void> refresh() async {
    ref.invalidateSelf();
    // invalidate 的调用在同步阶段使旧分页代次失效。
    _generation = Object();
    await future;
  }

  Future<void> loadMore({bool retry = false}) async {
    final before = state.value;
    if (before == null ||
        !isCurrent(before) ||
        before.next == null ||
        before.loadingMore ||
        (!retry && before.error != null)) {
      return;
    }
    final owner = ref;
    final generation = _generation;
    bool current() =>
        owner.mounted &&
        identical(generation, _generation) &&
        isCurrent(before);
    state = AsyncData(before.operation(loadingMore: true));
    try {
      final items = [...before.items];
      final seen = items.map(itemKey).toSet();
      final cursors = <Object>{};
      Object? cursor = before.next;
      M metadata = before.metadata;
      var exhausted = false;
      // 重复页和过滤后空页有限补位，避免后台持续请求。
      for (var budget = 0; budget < 5 && cursor != null; budget++) {
        if (!cursors.add(cursor)) {
          cursor = null;
          break;
        }
        final page = await fetch(before.account, cursor);
        if (!current()) return;
        final length = items.length;
        items.addAll(page.items.where((item) => seen.add(itemKey(item))));
        metadata = mergeMetadata(metadata, page.metadata);
        cursor = page.next;
        if (cursor != null && cursors.contains(cursor)) cursor = null;
        if (items.length > length) break;
        if (budget == 4) {
          if (endOnEmptyBudget) cursor = null;
          exhausted = true;
        }
      }
      if (current()) {
        state = AsyncData(
          FeedState(
            items: items,
            metadata: metadata,
            account: before.account,
            source: before.source,
            next: cursor,
            error: exhausted && cursor != null
                ? const Error('连续五页没有新增内容，请继续加载')
                : null,
          ),
        );
      }
    } catch (error, stack) {
      if (current()) {
        state = AsyncData(
          before.operation(
            error: error is Error ? error : Error.fromException(error, stack),
          ),
        );
      }
    }
  }
}
