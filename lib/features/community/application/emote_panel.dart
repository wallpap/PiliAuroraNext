import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/emote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:pili_aurora_next/features/community/domain/emote/emote.dart';
import 'package:pili_aurora_next/features/community/domain/emote/recent_emote.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final emotePackagesProvider = NotifierProvider.autoDispose
    .family<EmotePackages, DiscoveryListingState<Package, void>, Object>(
      EmotePackages.new,
    );

class EmotePackages extends DiscoveryListing<Package, void> {
  EmotePackages(this.owner);
  final Object owner;
  @override
  bool get filterAuthors => false;
  @override
  bool get usesMainAccount => true;
  @override
  bool get paginated => false;
  @override
  Future<LoadingState<DiscoveryPage<Package, void>>> fetch(
    Account account,
    int page,
  ) async =>
      switch (await ref.read(emoteRepositoryProvider).packages(account)) {
        Success(:final response) => Success(
          DiscoveryPage(response ?? [], metadata: null, hasMore: false),
        ),
        Error error => error,
        _ => LoadingState.loading(),
      };
}

final recentEmotesProvider = NotifierProvider<RecentEmotes, List<RecentEmote>>(
  RecentEmotes.new,
);

class RecentEmotes extends Notifier<List<RecentEmote>> {
  Future<void> _saving = Future.value();
  @override
  List<RecentEmote> build() => ref.read(emoteRepositoryProvider).history();
  Future<void> record(Emote emote, double? width) {
    state = List.unmodifiable(
      [
        RecentEmote(Emote(text: emote.text, url: emote.url), width),
        ...state.where(
          (item) =>
              item.emote.text != emote.text || item.emote.url != emote.url,
        ),
      ].take(40),
    );
    final snapshot = state;
    final repository = ref.read(emoteRepositoryProvider);
    return _saving = _saving.then((_) => repository.saveHistory(snapshot));
  }
}
