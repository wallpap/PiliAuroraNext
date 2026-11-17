import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/group.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/top_details.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/features/community/domain/topic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final topicRepositoryProvider = Provider((ref) => const TopicRepository());

class TopicRepository {
  const TopicRepository();
  Future<LoadingState<TopDetails?>> top(Account account, String id) async {
    final result = await DynamicsHttp.topicTop(account: account, topicId: id);
    if (result case Success(:final response) when response?.topicItem == null) {
      return const Error('话题信息不完整，请重试');
    }
    return result;
  }

  Future<LoadingState<DiscoveryPage<TopicCardItem, TopicCursor>>> feed(
    Account account,
    String id,
    int sort,
    TopicCursor? cursor,
  ) async {
    final result = await DynamicsHttp.topicFeed(
      account: account,
      topicId: id,
      sortBy: sort,
      offset: cursor?.offset,
    );
    if (result case Success(:final response)) {
      if (response == null) return const Error('话题内容不完整，请重试');
      final offset = response.offset;
      final seen = {...?cursor?.seen};
      final more =
          response.hasMore != false &&
          offset != null &&
          offset.isNotEmpty &&
          seen.add(offset);
      return Success(
        DiscoveryPage(
          response.items ?? [],
          metadata: TopicCursor(
            offset,
            Set.unmodifiable(seen),
            response.topicSortByConf,
          ),
          hasMore: more,
        ),
      );
    }
    return result as Error;
  }

  Future<LoadingState<List<TopicCardItem>>> fold(
    Account account,
    String id,
    int sort,
  ) async => switch (await DynamicsHttp.topicFold(
    account: account,
    topicId: id,
    sortBy: sort,
  )) {
    Success(:final response) when response?.items != null => Success(
      response!.items!,
    ),
    Error error => error,
    _ => const Error('展开内容不完整，请重试'),
  };

  Future<LoadingState<DiscoveryPage<TopicItem, void>>> recommended(
    Account account,
  ) async => switch (await DynamicsHttp.dynTopicRcmd(account: account)) {
    Success(:final response) => Success(
      DiscoveryPage(response ?? [], metadata: null, hasMore: false),
    ),
    Error error => error,
    _ => const Error('话题加载失败'),
  };

  Future<LoadingState<DiscoveryPage<TopicItem, void>>> search(
    Account account,
    String keyword,
    int page,
  ) async => switch (await SearchHttp.topicPubSearch(
    account: account,
    keywords: keyword,
    pageNum: page,
  )) {
    Success(:final response) => Success(
      DiscoveryPage(
        response.topicItems ?? [],
        metadata: null,
        hasMore: response.pageInfo?.hasMore,
      ),
    ),
    Error error => error,
    _ => const Error('话题加载失败'),
  };

  Future<LoadingState<DiscoveryPage<MentionGroup, void>>> mentions(
    Account account,
    String keyword,
  ) async => switch (await DynamicsHttp.dynMention(
    account: account,
    keyword: keyword,
  )) {
    Success(:final response) => Success(
      DiscoveryPage(response ?? [], metadata: null, hasMore: false),
    ),
    Error error => error,
    _ => const Error('用户加载失败'),
  };

  Future<LoadingState<void>> favorite(
    Account account,
    String id,
    bool wasFavorite,
  ) => wasFavorite
      ? FavHttp.delFavTopic(id, account: account)
      : FavHttp.addFavTopic(id, account: account);
  Future<LoadingState<void>> like(Account account, String id, bool wasLiked) =>
      FavHttp.likeTopic(id, wasLiked, account: account);
}
