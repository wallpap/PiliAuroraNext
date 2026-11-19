import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/reply_search.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show SearchItem, SearchItemType, SearchItemVideoSubType;
import 'package:pili_aurora_next/grpc/reply.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final replySearchRepositoryProvider = Provider(
  (ref) => const ReplySearchRepository(),
);

class ReplySearchRepository {
  const ReplySearchRepository();

  Future<LoadingState<DiscoveryPage<ReplySearchEntry, void>>> search({
    required Account account,
    required ReplySearchType kind,
    required int type,
    required int oid,
    required String keyword,
    required int page,
  }) async {
    final result = await ReplyGrpc.searchItem(
      account: account,
      page: page,
      itemType: switch (kind) {
        .video => SearchItemType.VIDEO,
        .article => SearchItemType.ARTICLE,
      },
      oid: oid,
      type: type,
      keyword: keyword,
    );
    if (result case Success(:final response)) {
      return Success(
        DiscoveryPage(
          [for (final item in response.items) _entry(item, kind)],
          metadata: null,
          hasMore: response.cursor.hasNext && response.items.isNotEmpty,
        ),
      );
    }
    return result as Error;
  }

  ReplySearchEntry _entry(SearchItem item, ReplySearchType kind) {
    if (kind == .article) {
      final article = item.article;
      return ReplySearchEntry(
        title: article.title,
        cover: article.covers.firstOrNull ?? '',
        author: article.upNickname,
        url: item.url,
      );
    }
    final video = item.video;
    if (video.type == SearchItemVideoSubType.UGC) {
      final ugc = video.ugc;
      return ReplySearchEntry(
        title: ugc.title,
        cover: ugc.cover,
        author: ugc.upNickname,
        duration: ugc.duration.toInt(),
        url: item.url,
      );
    }
    final pgc = video.pgc;
    return ReplySearchEntry(
      title: pgc.title,
      cover: pgc.cover,
      category: pgc.category,
      url: item.url,
    );
  }
}
