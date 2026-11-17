import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/topic_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/group.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/features/community/domain/topic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef TopicQuery = ({Object owner, String id, int sort});
final topicFeedProvider = NotifierProvider.autoDispose
    .family<
      TopicFeed,
      DiscoveryListingState<TopicCardItem, TopicCursor>,
      TopicQuery
    >(TopicFeed.new);

class TopicFeed extends DiscoveryListing<TopicCardItem, TopicCursor> {
  TopicFeed(this.query);
  final TopicQuery query;
  Object? _folding;
  Object? _foldingSource;
  int? _effectiveSort;
  final _removed = <String>{};
  @override
  DiscoveryListingState<TopicCardItem, TopicCursor> build() {
    final account = ref.watch(mainAccountProvider);
    final subscription = ref.read(dynamicsUpdatesProvider).changes.listen((
      change,
    ) {
      if (!ref.mounted || !identical(account, change.account)) return;
      if (change.removed == null) {
        unawaited(onRefresh());
      } else {
        _removed.add(change.removed!);
        excludeKey(change.removed!);
      }
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return super.build();
  }

  @override
  Object itemKey(TopicCardItem item) =>
      item.dynamicCardItem?.idStr?.toString() ?? item;
  @override
  Future<LoadingState<DiscoveryPage<TopicCardItem, TopicCursor>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final result = await ref
        .read(topicRepositoryProvider)
        .feed(
          account,
          query.id,
          _effectiveSort ?? query.sort,
          queryMetadata,
        );
    if (current()) {
      if (result case Success(:final response)) {
        _effectiveSort = response.metadata.sort?.showSortBy ?? _effectiveSort;
      }
    }
    return result;
  }

  Future<LoadingState<void>> unfold() async {
    final current = captureQuery();
    final source = state.source;
    final items = state.loading.dataOrNull;
    final fold = items?.where((item) => item.foldCardItem != null).firstOrNull;
    if (identical(_foldingSource, source) ||
        state.loadingMore ||
        fold == null) {
      return const Error('内容已更新或正在加载');
    }
    final operation = _folding = Object();
    _foldingSource = source;
    final account = ref.read(recommendAccountProvider);
    final sort = _effectiveSort ?? query.sort;
    final filter = ref.read(discoveryFilterProvider);
    final authors = ref.read(cooperativeAuthorsProvider);
    try {
      final result = await ref
          .read(topicRepositoryProvider)
          .fold(account, query.id, sort);
      if (!current() || !identical(source, state.source)) {
        return const Error('话题已更新');
      }
      if (result case Error error) return error;
      await filter.prepare();
      if (!current()) return const Error('话题已更新');
      final videos = filter.authorsToCheck(result.data).toList();
      if (videos.isNotEmpty) {
        await authors.prepare(videos, isCurrent: current);
      }
      if (!current()) return const Error('话题已更新');
      final latest = state.loading.dataOrNull;
      if (latest == null || !latest.contains(fold)) return const Error('话题已更新');
      // 展开按最新分页快照合并，不能丢失展开期间到达的续页。
      final seen = latest
          .where((item) => !identical(item, fold))
          .map(itemKey)
          .toSet();
      final additions = filter.filter(
        result.data.where(
          (item) =>
              !_removed.contains(itemKey(item)) && seen.add(itemKey(item)),
        ),
      );
      final updated = List<TopicCardItem>.of(latest);
      final index = updated.indexOf(fold);
      // 空结果保留展开入口，用户仍可重试。
      if (result.data.isNotEmpty) {
        updated
          ..removeAt(index)
          ..insertAll(index, additions);
      }
      state = DiscoveryListingState(
        source: source,
        loading: Success(List.unmodifiable(updated)),
        metadata: state.metadata,
        loadingMore: state.loadingMore,
        hasMore: state.hasMore,
        error: state.error,
      );
      return const Success(null);
    } catch (cause, stack) {
      return Error.fromException(cause, stack);
    } finally {
      if (identical(_folding, operation)) {
        _folding = _foldingSource = null;
      }
    }
  }
}

final recommendedTopicsProvider = NotifierProvider.autoDispose
    .family<RecommendedTopics, DiscoveryListingState<TopicItem, void>, Object>(
      RecommendedTopics.new,
    );

class RecommendedTopics extends DiscoveryListing<TopicItem, void> {
  RecommendedTopics(this.owner);
  final Object owner;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => false;
  @override
  bool get paginated => false;
  @override
  Object itemKey(TopicItem item) => item.id;
  @override
  Future<LoadingState<DiscoveryPage<TopicItem, void>>> fetch(
    Account account,
    int page,
  ) => ref.read(topicRepositoryProvider).recommended(account);
}

typedef CommunityLookup = ({Object owner, String keyword, bool debounce});
final topicSearchProvider = NotifierProvider.autoDispose
    .family<
      TopicSearch,
      DiscoveryListingState<TopicItem, void>,
      CommunityLookup
    >(TopicSearch.new);

class TopicSearch extends DiscoveryListing<TopicItem, void> {
  TopicSearch(this.query);
  final CommunityLookup query;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  Object itemKey(TopicItem item) => item.id;
  @override
  Future<LoadingState<DiscoveryPage<TopicItem, void>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final repository = ref.read(topicRepositoryProvider);
    if (page == 1 && query.debounce) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!current()) return const Error('查询已更新');
    return repository.search(account, query.keyword, page);
  }
}

final mentionSearchProvider = NotifierProvider.autoDispose
    .family<
      MentionSearch,
      DiscoveryListingState<MentionGroup, void>,
      CommunityLookup
    >(MentionSearch.new);

class MentionSearch extends DiscoveryListing<MentionGroup, void> {
  MentionSearch(this.query);
  final CommunityLookup query;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<MentionGroup, void>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final repository = ref.read(topicRepositoryProvider);
    if (query.debounce) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!current()) return const Error('查询已更新');
    return repository.mentions(account, query.keyword);
  }
}
