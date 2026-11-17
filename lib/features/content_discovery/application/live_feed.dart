import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/live_catalog_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef LiveQuery = ({
  Object owner,
  int? areaId,
  int? parentAreaId,
  String? sortType,
});
final liveFeedProvider = NotifierProvider.autoDispose
    .family<
      LiveFeed,
      DiscoveryListingState<CardLiveItem, LiveCatalog>,
      LiveQuery
    >(LiveFeed.new);

class LiveFeed extends DiscoveryListing<CardLiveItem, LiveCatalog> {
  LiveFeed(this.query);
  final LiveQuery query;
  @override
  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final result = await ref
        .read(liveCatalogRepositoryProvider)
        .home(
          account,
          page,
          areaId: query.areaId,
          parentAreaId: query.parentAreaId,
          sortType: query.sortType,
          previous: queryMetadata,
          isCurrent: current,
        );
    if (!current()) return LoadingState.loading();
    if (page == 1) {
      if (result case Success(:final response)) {
        final followed = response.metadata.followed?.cardData?.myIdolV1;
        if (followed?.list case final list?) {
          followed!.list = ref
              .read(discoveryFilterProvider)
              .filter(list, deduplicate: true);
        }
      }
    }
    return result;
  }
}
