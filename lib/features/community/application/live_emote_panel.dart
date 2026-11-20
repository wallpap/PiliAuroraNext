import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/emote_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/live_emote/datum.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef LiveEmoteQuery = ({Object owner, int roomId});
final liveEmotePackagesProvider = NotifierProvider.autoDispose
    .family<
      LiveEmotePackages,
      DiscoveryListingState<LiveEmoteDatum, void>,
      LiveEmoteQuery
    >(LiveEmotePackages.new);

class LiveEmotePackages extends DiscoveryListing<LiveEmoteDatum, void> {
  LiveEmotePackages(this.query);
  final LiveEmoteQuery query;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<LiveEmoteDatum, void>>> fetch(
    Account account,
    int page,
  ) async => switch (await ref
      .read(emoteRepositoryProvider)
      .livePackages(account, query.roomId)) {
    Success(:final response) => Success(
      DiscoveryPage(response ?? [], metadata: null, hasMore: false),
    ),
    Error error => error,
    _ => LoadingState.loading(),
  };
}
