import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/watch_later/domain/data.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_folder/list.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class LaterRepository {
  Future<LaterData> page(
    Account account, {
    required int page,
    required int viewed,
    required String keyword,
    required bool asc,
  }) async => (await UserHttp.seeYouLater(
    account: account,
    page: page,
    viewed: viewed,
    keyword: keyword,
    asc: asc,
  )).data;
  Future<LoadingState<void>> add(
    Account account, {
    String? bvid,
    Object? aid,
  }) => UserHttp.toViewLater(account: account, bvid: bvid, aid: aid);
  Future<LoadingState<void>> remove(Account account, Iterable<int> aids) =>
      UserHttp.toViewDel(account: account, aids: aids.join(','));
  Future<LoadingState<void>> clear(Account account, int? type) =>
      UserHttp.toViewClear(account: account, cleanType: type);
  Future<List<FavFolderInfo>> folders(Account account) async =>
      (await FavHttp.allFavFolders(account.mid, account: account)).data.list ??
      [];
  Future<LoadingState<void>> transfer(
    Account account,
    List<int> aids,
    int folder,
    bool copy,
  ) => FavHttp.copyOrMoveFav(
    account: account,
    isCopy: copy,
    isFav: false,
    srcMediaId: null,
    tarMediaId: folder,
    resources: aids.join(','),
    mid: copy ? account.mid : null,
  );
}
