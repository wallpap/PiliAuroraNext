import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/rank_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef RankQuery = ({Object owner, int? rid, int? seasonType});
final rankFeedProvider = NotifierProvider.autoDispose
    .family<RankFeed, DiscoveryListingState<Object, void>, RankQuery>(
      RankFeed.new,
    );

class RankFeed extends DiscoveryListing<Object, void> {
  RankFeed(this.query);
  final RankQuery query;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<Object, void>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(rankRepositoryProvider)
      .fetch(account, rid: query.rid, seasonType: query.seasonType);
}
