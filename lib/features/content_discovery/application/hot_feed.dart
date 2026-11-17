import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/hot_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final hotFeedProvider = NotifierProvider.autoDispose
    .family<HotFeed, DiscoveryListingState<HotVideoItemModel, void>, Object>(
      (key) => HotFeed(),
    );

class HotFeed extends DiscoveryListing<HotVideoItemModel, void> {
  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, void>>> fetch(
    Account account,
    int page,
  ) => ref.read(hotRepositoryProvider).fetch(account, page);
}
