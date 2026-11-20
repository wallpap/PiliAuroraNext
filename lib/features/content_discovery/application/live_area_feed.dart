import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/live_catalog_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_area.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live/feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef LiveDirectoryQuery = ({Object owner, Object? parentId});
final liveDirectoryProvider = NotifierProvider.autoDispose
    .family<
      LiveDirectory,
      DiscoveryListingState<AreaItem, void>,
      LiveDirectoryQuery
    >(LiveDirectory.new);

class LiveDirectory extends DiscoveryListing<AreaItem, void> {
  LiveDirectory(this.query);
  final LiveDirectoryQuery query;
  @override
  bool get paginated => false;
  @override
  bool get filterAuthors => false;
  @override
  Future<LoadingState<DiscoveryPage<AreaItem, void>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(liveCatalogRepositoryProvider)
      .directory(account, query.parentId);
}

typedef LiveAreaQuery = ({
  Object owner,
  Object? areaId,
  Object? parentAreaId,
  String? sortType,
});
final liveAreaFeedProvider = NotifierProvider.autoDispose
    .family<
      LiveAreaFeed,
      DiscoveryListingState<CardLiveItem, LiveCatalog>,
      LiveAreaQuery
    >(LiveAreaFeed.new);

class LiveAreaFeed extends DiscoveryListing<CardLiveItem, LiveCatalog> {
  LiveAreaFeed(this.query);
  final LiveAreaQuery query;
  @override
  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(liveCatalogRepositoryProvider)
      .area(
        account,
        page,
        areaId: query.areaId,
        parentAreaId: query.parentAreaId,
        sortType: query.sortType,
        previous: queryMetadata,
      );
}
