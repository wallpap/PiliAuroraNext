import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/curated_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/weekly_catalog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef WeeklyQuery = ({Object owner, int? number});
final weeklyFeedProvider = NotifierProvider.autoDispose
    .family<
      WeeklyFeed,
      DiscoveryListingState<HotVideoItemModel, WeeklyCatalog>,
      WeeklyQuery
    >(WeeklyFeed.new);

class WeeklyFeed extends DiscoveryListing<HotVideoItemModel, WeeklyCatalog> {
  WeeklyFeed(this.query);
  final WeeklyQuery query;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, WeeklyCatalog>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(curatedRepositoryProvider)
      .weekly(account, query.number, isCurrent: captureQuery());
}

final preciousFeedProvider = NotifierProvider.autoDispose
    .family<
      PreciousFeed,
      DiscoveryListingState<HotVideoItemModel, ({int? mediaId})>,
      Object
    >((owner) => PreciousFeed());

class PreciousFeed
    extends DiscoveryListing<HotVideoItemModel, ({int? mediaId})> {
  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, ({int? mediaId})>>>
  fetch(Account account, int page) =>
      ref.read(curatedRepositoryProvider).precious(account, page);
}
