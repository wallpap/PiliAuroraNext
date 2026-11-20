import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/data/related_video_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final class RelatedVideoQuery {
  RelatedVideoQuery(this.bvid);

  final String bvid;
}

typedef RelatedVideosState = DiscoveryListingState<HotVideoItemModel, void>;

final relatedVideosProvider = NotifierProvider.autoDispose
    .family<RelatedVideos, RelatedVideosState, RelatedVideoQuery>(
      RelatedVideos.new,
    );

class RelatedVideos extends DiscoveryListing<HotVideoItemModel, void> {
  RelatedVideos(this.query);
  final RelatedVideoQuery query;

  @override
  bool get paginated => false;

  @override
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, void>>> fetch(
    Account account,
    int page,
  ) => RelatedVideoRepository.load(account, query.bvid);
}
