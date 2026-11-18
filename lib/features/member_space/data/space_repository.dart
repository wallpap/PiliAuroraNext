import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/models/common/member/archive_order_type_app.dart';
import 'package:pili_aurora_next/models/common/member/archive_order_type_web.dart';
import 'package:pili_aurora_next/models/common/member/archive_sort_type_app.dart';
import 'package:pili_aurora_next/models/common/member/web_ss_type.dart';
import 'package:pili_aurora_next/models/remote/member/search_archive/data.dart';
import 'package:pili_aurora_next/models/remote/member/season_web/data.dart';
import 'package:pili_aurora_next/models/remote/pagelist/page_item.dart';
import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/member_favorites.dart';
import 'package:pili_aurora_next/models/remote/space/space_fav/data.dart';
import 'package:pili_aurora_next/models/common/member/contribute_type.dart';
import 'package:pili_aurora_next/models/remote/space/space_archive/data.dart';
import 'package:pili_aurora_next/models/remote/space/space_opus/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/remote/space/space/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_medal_wall/data.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final spaceRepositoryProvider = Provider((ref) => const SpaceRepository());

class SpaceRepository {
  const SpaceRepository();

  Future<LoadingState<SpaceData>> space(
    Account account,
    int mid,
    String? aid,
  ) => MemberHttp.space(account: account, mid: mid, fromViewAid: aid);

  Future<LoadingState<SpaceArchiveData>> archives(
    Account account,
    int mid,
    ContributeType type, {
    String? anchor,
    ArchiveOrderTypeApp? order,
    ArchiveSortTypeApp? sort,
    int? page,
    int? cursor,
    int? season,
    int? series,
    bool? includeCursor,
  }) => MemberHttp.spaceArchive(
    account: account,
    mid: mid,
    type: type,
    aid: anchor,
    order: order,
    sort: sort,
    pn: page,
    next: cursor,
    seasonId: season,
    seriesId: series,
    includeCursor: includeCursor,
  );

  Future<LoadingState<SearchArchiveData>> webArchive(
    Account account,
    Object mid,
    int page,
    ArchiveOrderTypeWeb order,
    int tid,
    String? specialType,
  ) => MemberHttp.searchArchive(
    account: account,
    mid: mid,
    pn: page,
    order: order,
    tid: tid,
    specialType: specialType,
  );

  Future<LoadingState<SeasonWebData>> webCollection(
    Account account,
    Object mid,
    WebSsType type,
    Object id,
    int page,
    ArchiveSortTypeApp sort,
  ) => MemberHttp.seasonSeriesWeb(
    account: account,
    mid: mid,
    type: type,
    id: id,
    pn: page,
    sort: sort,
  );

  Future<LoadingState<PageItem?>> videoPart(
    Account account,
    int aid,
    String bvid,
  ) => SearchHttp.pageWithDimension(account: account, aid: aid, bvid: bvid);

  Future<LoadingState<SpaceArchiveData>> bangumi(
    Account account,
    int mid,
    int page,
  ) => MemberHttp.spaceArchive(
    account: account,
    type: ContributeType.bangumi,
    mid: mid,
    pn: page,
  );

  Future<LoadingState<SpaceOpusData>> opus(
    Account account,
    int mid,
    int page,
    String offset,
    String filter,
  ) => MemberHttp.spaceOpus(
    account: account,
    hostMid: mid,
    page: page,
    offset: offset,
    type: filter,
  );

  Future<LoadingState<void>> relation(Account account, int mid, int action) =>
      VideoHttp.relationMod(account: account, mid: mid, act: action, reSrc: 11);

  Future<LoadingState<void>> claimExperience(Account account) =>
      UserHttp.vipExpAdd(account: account);

  Future<LoadingState<int?>> followTime(Account account, int mid) async =>
      switch (await UserHttp.userRelation(mid, account: account)) {
        Success(:final response) => Success(response.mtime),
        Error error => error,
        Loading() => LoadingState<int?>.loading(),
      };

  Future<LoadingState<void>> reserve(Account account, int sid, bool isFollow) =>
      UserHttp.spaceReserve(sid: sid, isFollow: isFollow, account: account);

  Future<LoadingState<List<SpaceFavData>?>> favorites(
    Account account,
    int mid,
  ) => FavHttp.spaceFav(mid: mid, account: account);

  Future<LoadingState<MemberFavoritePage>> favoriteFolders(
    Account account,
    int mid,
    int page,
    bool subscribed,
  ) => MemberFavoritesHttp.folders(
    account: account,
    mid: mid,
    page: page,
    subscribed: subscribed,
  );

  Future<LoadingState<MedalWallData>> medals(int mid) =>
      LiveHttp.liveMedalWall(mid: mid);
}
