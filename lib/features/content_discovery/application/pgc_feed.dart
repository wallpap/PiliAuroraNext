import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/pgc_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_pgc/list.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/pgc/index_result/list.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/pgc/timeline/result.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef PgcQuery = ({Object owner, bool cinema});
final pgcFeedProvider = NotifierProvider.autoDispose
    .family<PgcFeed, DiscoveryListingState<PgcIndexItem, void>, PgcQuery>(
      PgcFeed.new,
    );
final pgcFollowsProvider = NotifierProvider.autoDispose
    .family<PgcFollows, DiscoveryListingState<FavPgcItemModel, int>, PgcQuery>(
      PgcFollows.new,
    );
final pgcTimelineProvider = NotifierProvider.autoDispose
    .family<
      PgcTimeline,
      DiscoveryListingState<TimelineResult, String?>,
      Object
    >(PgcTimeline.new);

class PgcFeed extends DiscoveryListing<PgcIndexItem, void> {
  PgcFeed(this.query);
  final PgcQuery query;
  @override
  bool get filterAuthors => false;
  @override
  Object itemKey(PgcIndexItem item) => item.seasonId ?? item;
  @override
  Future<LoadingState<DiscoveryPage<PgcIndexItem, void>>> fetch(
    Account account,
    int page,
  ) => ref.read(pgcRepositoryProvider).catalog(account, page, query.cinema);
}

class PgcFollows extends DiscoveryListing<FavPgcItemModel, int> {
  PgcFollows(this.query);
  final PgcQuery query;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  Object itemKey(FavPgcItemModel item) => item.seasonId ?? item;
  @override
  Future<LoadingState<DiscoveryPage<FavPgcItemModel, int>>> fetch(
    Account account,
    int page,
  ) => ref.read(pgcRepositoryProvider).follows(account, page, query.cinema);
}

class PgcTimeline extends DiscoveryListing<TimelineResult, String?> {
  PgcTimeline(this.owner);
  final Object owner;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<TimelineResult, String?>>> fetch(
    Account account,
    int page,
  ) => ref.read(pgcRepositoryProvider).timeline(account);
}
