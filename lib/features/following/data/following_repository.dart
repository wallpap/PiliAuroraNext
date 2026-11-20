import 'package:pili_aurora_next/features/following/domain/following.dart';
import 'package:pili_aurora_next/http/fan.dart';
import 'package:pili_aurora_next/http/follow.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/following/domain/follow_order_type.dart';
import 'package:pili_aurora_next/features/following/domain/list/data.dart';
import 'package:pili_aurora_next/features/following/domain/live/data.dart';
import 'package:pili_aurora_next/features/following/domain/relation/data.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

class FollowingRepository {
  const FollowingRepository();

  FollowOrderType get order => Pref.followOrderType;

  Future<void> saveOrder(FollowOrderType order) =>
      GStorage.setting.put(SettingBoxKey.followOrderType, order.index);

  Future<FollowData> following({
    required Account account,
    required int mid,
    required int page,
    required int pageSize,
    required FollowOrderType order,
    int? tag,
    String? keyword,
  }) async {
    final result = keyword != null
        ? await MemberHttp.followSearch(
            account: account,
            mid: mid,
            ps: pageSize,
            pn: page,
            name: keyword,
          )
        : tag != null
        ? await MemberHttp.followUpGroup(
            account: account,
            mid: mid,
            tagid: tag,
            pn: page,
            orderType: order.type,
          )
        : await FollowHttp.followings(
            account: account,
            vmid: mid,
            pn: page,
            orderType: order.type,
          );
    return result.data;
  }

  Future<FollowData> relations({
    required Account account,
    required FollowKind kind,
    required int mid,
    required int page,
    required int pageSize,
    required bool newestFirst,
  }) async {
    final result = switch (kind) {
      FollowKind.fans => await FanHttp.fans(
        vmid: mid,
        pn: page,
        ps: pageSize,
        orderType: newestFirst ? null : 'attention',
        account: account,
      ),
      FollowKind.same => await UserHttp.sameFollowing(
        mid: mid,
        pn: page,
        account: account,
      ),
      FollowKind.followed => await UserHttp.followedUp(
        mid: mid,
        pn: page,
        account: account,
      ),
    };
    return result.data;
  }

  Future<LiveFollowData> liveFollowing(Account account, int page) async =>
      (await LiveHttp.liveFollow(page, account: account)).data;

  Future<String?> memberName(Account account, int mid) async =>
      (await MemberHttp.memberCardInfo(
        mid: mid,
        account: account,
      )).dataOrNull?.card?.name;

  Future<LoadingState<RelationData>> relation(Account account, int mid) =>
      UserHttp.userRelation(mid, account: account);

  Future<LoadingState<void>> setFollowing(
    Account account,
    int mid,
    bool follow,
  ) => VideoHttp.relationMod(
    account: account,
    mid: mid,
    act: follow ? 1 : 2,
    reSrc: 11,
  );

  Future<LoadingState<void>> setSpecial(
    Account account,
    int mid,
    bool enabled,
  ) => MemberHttp.specialAction(account: account, fid: mid, isAdd: enabled);

  Future<LoadingState<void>> updateFan(
    Account account,
    int mid, {
    required bool remove,
    required bool isFollowing,
  }) => VideoHttp.relationMod(
    account: account,
    mid: mid,
    act: remove
        ? 7
        : isFollowing
        ? 2
        : 1,
    reSrc: remove ? 11 : 107,
  );

  Future<List<FollowTag>> tags(Account account) async {
    final result = await MemberHttp.followUpTags(account: account);
    final ids = <int>{};
    return [
      for (final tag in result.data)
        if (tag.tagid case final id? when ids.add(id))
          FollowTag(
            id: id,
            name: tag.name ?? '',
            count: tag.count,
            tip: tag.tip,
          ),
    ];
  }

  Future<LoadingState<int>> createTag(Account account, String name) =>
      MemberHttp.createFollowTag(name, account: account);

  Future<LoadingState<void>> renameTag(Account account, int id, String name) =>
      MemberHttp.updateFollowTag(id, name, account: account);

  Future<LoadingState<void>> deleteTag(Account account, int id) =>
      MemberHttp.delFollowTag(id, account: account);

  Future<LoadingState<void>> sortTags(Account account, List<int> order) =>
      FollowHttp.sortFollowTag(account: account, tagids: order.join(','));

  Future<LoadingState<void>> assignTags(
    Account account,
    int mid,
    Set<int> ids,
  ) => MemberHttp.addUsers(
    '$mid',
    ids.isEmpty ? '0' : ids.join(','),
    account: account,
  );
}
