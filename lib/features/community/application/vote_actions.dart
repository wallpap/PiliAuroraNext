import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/community/data/vote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/vote.dart';
import 'package:pili_aurora_next/features/community/domain/votes/vote.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

abstract final class VoteActions {
  static const _repository = VoteRepository();

  static Future<LoadingState<List<FolloweeVote>?>> followees(
    Account account,
    int? id,
  ) => _repository.followees(account, id);

  static Future<LoadingState<VoteInfo>> detail(Account account, int id) =>
      _repository.detail(account, id);

  static Future<LoadingState<VoteInfo>> vote(
    Account account,
    int id,
    Set<int> selected,
    bool anonymous,
    int? dynamicId,
  ) => _repository.vote(account, id, selected, anonymous, dynamicId);
}
