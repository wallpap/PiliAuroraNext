import 'package:pili_aurora_next/features/following/data/following_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/relation/data.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class FollowActions {
  const FollowActions();

  static const _repository = FollowingRepository();

  Account get account => Accounts.main;

  bool owns(Account owner) => identical(owner, account);

  Future<LoadingState<RelationData>> relation(Account owner, int mid) =>
      _repository.relation(owner, mid);

  Future<LoadingState<void>> setFollowing(
    Account owner,
    int mid,
    bool follow,
  ) => _repository.setFollowing(owner, mid, follow);

  Future<LoadingState<void>> setSpecial(Account owner, int mid, bool enabled) =>
      _repository.setSpecial(owner, mid, enabled);
}
