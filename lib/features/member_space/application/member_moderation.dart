import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final class MemberModeration {
  MemberModeration.capture() : _account = Accounts.main;

  final Account _account;
  bool get isCurrent => identical(_account, Accounts.main);

  Future<LoadingState<void>> report(
    int memberId, {
    required Iterable<int> reasons,
    int? additionalReason,
  }) {
    if (!isCurrent) return Future.value(const Error('账号已切换'));
    return const SpaceRepository().reportMember(
      _account,
      memberId,
      reasons.join(','),
      additionalReason,
    );
  }

  Future<LoadingState<void>> block(int memberId) {
    if (!isCurrent) return Future.value(const Error('账号已切换'));
    return const SpaceRepository().relation(_account, memberId, 5);
  }
}
