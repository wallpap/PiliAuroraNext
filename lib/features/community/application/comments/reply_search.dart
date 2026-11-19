import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/reply_search_repository.dart';
import 'package:pili_aurora_next/features/community/domain/reply_search.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef ReplySearchQuery = ({
  Object submission,
  int type,
  int oid,
  ReplySearchType kind,
  String keyword,
});

final replySearchProvider = NotifierProvider.autoDispose
    .family<
      ReplySearch,
      DiscoveryListingState<ReplySearchEntry, void>,
      ReplySearchQuery
    >(ReplySearch.new);

class ReplySearch extends DiscoveryListing<ReplySearchEntry, void> {
  ReplySearch(this.query);

  final ReplySearchQuery query;

  @override
  bool get usesMainAccount => true;

  @override
  bool get filterAuthors => false;

  @override
  Object itemKey(ReplySearchEntry item) => item.url.isEmpty ? item : item.url;

  @override
  Future<LoadingState<DiscoveryPage<ReplySearchEntry, void>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(replySearchRepositoryProvider)
      .search(
        account: account,
        kind: query.kind,
        type: query.type,
        oid: query.oid,
        keyword: query.keyword,
        page: page,
      );
}
