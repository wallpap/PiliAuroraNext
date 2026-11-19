import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/search/domain/scoped_search.dart';
import 'package:pili_aurora_next/grpc/space.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/models/common/live/live_search_type.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/extension/dimension_ext.dart';

typedef ScopedSearchPage = ({
  List<dynamic> rows,
  int? total,
  String? offset,
  bool hasMore,
});

class ScopedSearchRepository {
  const ScopedSearchRepository();

  Future<ScopedSearchPage> page({
    required Account account,
    required ScopedSearchKind kind,
    required String keyword,
    required int page,
    int? mid,
    String? offset,
  }) async {
    switch (kind) {
      case ScopedSearchKind.room || ScopedSearchKind.user:
        final type = kind == ScopedSearchKind.room
            ? LiveSearchType.room
            : LiveSearchType.user;
        final data = (await LiveHttp.liveSearch(
          account: account,
          page: page,
          keyword: keyword,
          type: type,
        )).data;
        final rows = switch (type) {
          LiveSearchType.room => data.room?.list ?? [],
          LiveSearchType.user => data.user?.list ?? [],
        };
        final total = switch (type) {
          LiveSearchType.room => data.room?.totalRoom,
          LiveSearchType.user => data.user?.totalUser,
        };
        return (
          rows: rows,
          total: total,
          offset: null,
          hasMore:
              rows.isNotEmpty &&
              (total == null ? rows.length >= 30 : page * 30 < total),
        );
      case ScopedSearchKind.archive:
        final data = (await SpaceGrpc.searchArchive(
          account: account,
          keyword: keyword,
          mid: Int64(mid!),
          pn: page,
          ps: Int64(20),
        )).data;
        final rows = data.archives.map<ScopedSearchArchive>((item) {
          final archive = item.archive;
          return (
            aid: archive.aid.toInt(),
            cid: archive.firstCid.toInt(),
            title: archive.title,
            cover: archive.pic,
            author: archive.author.name,
            publishedAt: archive.pubdate.toInt(),
            duration: archive.duration.toInt(),
            views: archive.stat.view,
            danmaku: archive.stat.danmaku,
            isVertical: archive.dimension.isVertical,
            isCourse: item.isPugv,
            uri: item.uri,
            redirectUrl: archive.hasRedirectUrl() ? archive.redirectUrl : null,
          );
        }).toList();
        final total = data.total.toInt();
        return (
          rows: rows,
          total: total,
          offset: null,
          hasMore: rows.isNotEmpty && page * 20 < total,
        );
      case ScopedSearchKind.dynamic:
        final data = (await MemberHttp.dynSearch(
          account: account,
          pn: page,
          mid: mid!,
          offset: offset ?? '',
          keyword: keyword,
        )).data;
        final next = data.offset;
        return (
          rows: data.items ?? [],
          total: data.total,
          offset: next,
          hasMore:
              data.hasMore == true &&
              next != null &&
              next.isNotEmpty &&
              next != offset,
        );
    }
  }
}
