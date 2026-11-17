import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/up.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final dynamicsRepositoryProvider = Provider(
  (ref) => const DynamicsRepository(),
);

class DynamicsRepository {
  const DynamicsRepository();
  Future<LoadingState<FollowUpModel>> authors(
    Account account, {
    String? offset,
    int? followingPage,
  }) => followingPage != null
      ? DynamicsHttp.followings(
          account: account,
          vmid: account.mid,
          pn: followingPage,
          orderType: 'attention',
          ps: 50,
        )
      : offset == null
      ? DynamicsHttp.followUp(account: account)
      : DynamicsHttp.dynUpList(offset, account: account);
}
