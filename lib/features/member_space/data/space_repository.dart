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

  Future<LoadingState<MedalWallData>> medals(int mid) =>
      LiveHttp.liveMedalWall(mid: mid);
}
