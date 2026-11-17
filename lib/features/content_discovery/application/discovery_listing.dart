import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/services/cooperative_authors.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/media_author_filter.dart';

final discoveryFilterProvider = Provider<DiscoveryFilter>(
  (ref) => const DiscoveryFilter(),
);
final cooperativeAuthorsProvider = Provider<CooperativeAuthors>(
  (ref) => CooperativeAuthors.shared,
);

class DiscoveryListingState<T, M> {
  DiscoveryListingState({
    required this.source,
    LoadingState<List<T>>? loading,
    this.metadata,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  }) : loading = loading ?? LoadingState.loading();
  final Object source;
  final LoadingState<List<T>> loading;
  final M? metadata;
  final bool loadingMore, hasMore;
  final Error? error;
  bool get canLoadMore =>
      !loadingMore && hasMore && error == null && loading is Success;
}

class _Owner {
  _Owner(this.main, this.account);
  final Account main, account;
  bool disposed = false;
  int page = 1, count = 0;
  final removed = <Object>{};
}

/// 账号、刷新、合作作者检查与分页共同使用同一个查询所有者。
abstract class DiscoveryListing<T, M>
    extends Notifier<DiscoveryListingState<T, M>> {
  late _Owner _owner;
  bool get paginated => true;
  bool get filterAuthors => true;
  Future<LoadingState<DiscoveryPage<T, M>>> fetch(Account account, int page);

  @override
  DiscoveryListingState<T, M> build() {
    final owner = _owner = _Owner(
      ref.watch(mainAccountProvider),
      ref.watch(recommendAccountProvider),
    );
    ref.onDispose(() => owner.disposed = true);
    scheduleMicrotask(() {
      if (_current(owner)) unawaited(_load(owner));
    });
    return DiscoveryListingState(source: owner);
  }

  bool _current(_Owner owner) =>
      !owner.disposed &&
      ref.mounted &&
      identical(owner, _owner) &&
      identical(owner.main, ref.read(mainAccountProvider)) &&
      identical(owner.account, ref.read(recommendAccountProvider));

  /// 多步读取在每一步之前检查同一所有者，离页或刷新后停止后续请求。
  bool Function() captureQuery() {
    final owner = _owner;
    return () => _current(owner);
  }

  Future<void> onRefresh() {
    _owner.disposed = true;
    final owner = _owner = _Owner(
      ref.read(mainAccountProvider),
      ref.read(recommendAccountProvider),
    );
    state = DiscoveryListingState(source: owner);
    return _load(owner);
  }

  Future<void> onReload() => onRefresh();
  Future<void> onLoadMore() =>
      state.canLoadMore ? _load(_owner) : Future.value();
  Future<void> retry() =>
      state.loading is Success ? _load(_owner) : onRefresh();

  void remove(T item) {
    final items = state.loading.dataOrNull;
    if (items == null) return;
    _owner.removed.add(MediaAuthorFilter.contentKey(item) ?? item as Object);
    state = DiscoveryListingState(
      source: _owner,
      loading: Success(
        List.unmodifiable(items.where((value) => !identical(value, item))),
      ),
      metadata: state.metadata,
      loadingMore: state.loadingMore,
      hasMore: state.hasMore,
      error: state.error,
    );
  }

  Future<void> _load(_Owner owner) async {
    if (!_current(owner) || state.loadingMore) return;
    state = DiscoveryListingState(
      source: owner,
      loading: state.loading,
      metadata: state.metadata,
      loadingMore: true,
      hasMore: state.hasMore,
    );
    final filter = ref.read(discoveryFilterProvider);
    final authors = ref.read(cooperativeAuthorsProvider);
    var items = List<T>.of(state.loading.dataOrNull ?? []);
    M? metadata = state.metadata;
    var hasMore = state.hasMore;
    Error? error;
    try {
      if (filterAuthors) await filter.prepare();
      for (var attempt = 0; attempt < 5 && _current(owner); attempt++) {
        final result = await fetch(owner.account, owner.page);
        if (!_current(owner)) return;
        if (result case Error failure) {
          error = failure;
          break;
        }
        if (result is! Success<DiscoveryPage<T, M>>) break;
        final page = result.response;
        if (filterAuthors) {
          final videos = filter.authorsToCheck(page.items).toList();
          if (videos.isNotEmpty) {
            await authors.prepare(videos, isCurrent: () => _current(owner));
          }
        }
        if (!_current(owner)) return;
        items = List<T>.of(state.loading.dataOrNull ?? items);
        final candidates = page.items
            .where(
              (item) => !owner.removed.contains(
                MediaAuthorFilter.contentKey(item) ?? item,
              ),
            )
            .toList();
        final accepted = filterAuthors
            ? filter.filter(candidates, existing: items, deduplicate: true)
            : candidates;
        items.addAll(accepted);
        metadata = page.metadata;
        owner.count += page.items.length;
        owner.page++;
        hasMore =
            paginated &&
            (page.hasMore ?? page.items.isNotEmpty) &&
            (page.total == null || owner.count < page.total!);
        // 无增长预算耗尽后保留游标，关闭自动补读，允许用户显式继续。
        if (!hasMore || accepted.isNotEmpty) break;
        if (attempt == 4) error = const Error('连续多页无可展示内容，点击继续加载');
      }
    } catch (cause, stack) {
      error = Error.fromException(cause, stack);
    }
    if (!_current(owner)) return;
    state = DiscoveryListingState(
      source: owner,
      loading: error != null && owner.page == 1
          ? error
          : Success(List.unmodifiable(items)),
      metadata: metadata,
      hasMore: hasMore,
      error: error,
    );
  }
}
