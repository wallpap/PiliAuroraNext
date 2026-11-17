import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/bubble_repository.dart';
import 'package:pili_aurora_next/features/community/domain/bubble_catalog.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/bubble/dyn_list.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef BubbleQuery = ({
  Object owner,
  String tribeId,
  String? categoryId,
  int? sortType,
});
final bubbleFeedProvider = NotifierProvider.autoDispose
    .family<
      BubbleFeed,
      DiscoveryListingState<DynList, BubbleCatalog>,
      BubbleQuery
    >(BubbleFeed.new);

class BubbleFeed extends DiscoveryListing<DynList, BubbleCatalog> {
  BubbleFeed(this.query);
  final BubbleQuery query;
  @override
  bool get usesMainAccount => true;
  @override
  bool get filterAuthors => false;
  @override
  Object itemKey(DynList item) => item.dynId ?? item;
  @override
  Future<LoadingState<DiscoveryPage<DynList, BubbleCatalog>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(bubbleRepositoryProvider)
      .page(
        account,
        tribeId: query.tribeId,
        categoryId: query.categoryId,
        sortType: query.sortType,
        page: page,
        previous: queryMetadata,
      );
}
