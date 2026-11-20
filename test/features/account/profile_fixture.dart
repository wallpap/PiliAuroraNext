import 'dart:async';

import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/data/profile_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class FakeProfiles extends ProfileRepository {
  final requests = <Completer<LoadingState<UserInfoData>>>[];
  final owners = <Account>[];
  final saved = <UserInfoData>[];
  UserInfoData? cache;
  bool failCache = false;
  bool holdStats = false;
  final statRequests = <Completer<LoadingState<UserStat>>>[];
  final statOwners = <Account>[];
  Future<void> Function(Account, UserInfoData)? beforeSave;

  @override
  Future<LoadingState<UserStat>> stats(Account account) {
    statOwners.add(account);
    if (!holdStats) return Future.value(const Success(UserStat(follower: 7)));
    final request = Completer<LoadingState<UserStat>>();
    statRequests.add(request);
    return request.future;
  }

  @override
  UserInfoData? cached(Account account) =>
      cache?.mid == account.mid ? cache : null;
  @override
  Future<LoadingState<UserInfoData>> profile(Account account) {
    owners.add(account);
    final pending = Completer<LoadingState<UserInfoData>>();
    requests.add(pending);
    return pending.future;
  }

  @override
  Future<void> save(Account account, UserInfoData info) async {
    if (failCache) throw StateError('fixture');
    await beforeSave?.call(account, info);
    saved.add(info);
    cache = info;
  }
}

LoginAccount login(int mid, {String csrf = 'fixture'}) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': csrf}),
  null,
  null,
)..activated = true;
UserInfoData info(int mid, String name) => UserInfoData(
  mid: mid,
  uname: name,
  face: '$name.png',
  isLogin: true,
  money: 12,
);
