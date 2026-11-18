import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/live_catalog_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
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

final liveHomeHeaderProvider = FutureProvider.autoDispose
    .family<LoadingState<LiveCatalog>, Object>((ref, owner) async {
      final account = ref.watch(recommendAccountProvider);
      final main = ref.watch(mainAccountProvider);
      bool current() =>
          ref.mounted &&
          identical(account, ref.read(recommendAccountProvider)) &&
          identical(main, ref.read(mainAccountProvider));
      await ref.read(discoveryFilterProvider).prepare();
      if (!current()) return LoadingState.loading();
      final result = await ref
          .read(liveCatalogRepositoryProvider)
          .homeHeader(account);
      if (result case Success(:final response) when current()) {
        _filterFollowed(ref, response);
      }
      return result;
    }, retry: (_, _) => null);

void _filterFollowed(Ref ref, LiveCatalog catalog) {
  final followed = catalog.followed?.cardData?.myIdolV1;
  if (followed?.list case final list?) {
    followed!.list = ref
        .read(discoveryFilterProvider)
        .filter(list, deduplicate: true);
  }
}

class LiveFeed extends DiscoveryListing<CardLiveItem, LiveCatalog> {
  LiveFeed(this.query);
  final LiveQuery query;
  @override
  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final repository = ref.read(liveCatalogRepositoryProvider);
    final result = await (query.areaId == null
        ? repository.home(account, page, previous: queryMetadata)
        : repository.area(
            account,
            page,
            areaId: query.areaId,
            parentAreaId: query.parentAreaId,
            sortType: query.sortType,
            previous: queryMetadata,
          ));
    if (!current()) return LoadingState.loading();
    if (result case Success(:final response) when page == 1) {
      _filterFollowed(ref, response.metadata);
    }
    return result;
  }
}
