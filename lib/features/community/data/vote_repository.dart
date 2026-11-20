import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/vote_draft.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/msg.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/vote.dart';
import 'package:pili_aurora_next/models/remote/followee_votes/vote.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final voteRepositoryProvider = Provider((ref) => const VoteRepository());

class VoteRepository {
  const VoteRepository();
  Future<LoadingState<VoteInfo>> detail(Account account, int id) =>
      DynamicsHttp.voteInfo(id, account: account);

  Future<LoadingState<List<FolloweeVote>?>> followees(
    Account account,
    int? id,
  ) => DynamicsHttp.followeeVotes(voteId: id, account: account);

  Future<LoadingState<VoteInfo>> vote(
    Account account,
    int id,
    Set<int> selected,
    bool anonymous,
    int? dynamicId,
  ) => DynamicsHttp.doVote(
    account: account,
    voteId: id,
    votes: selected.toList(),
    anonymous: anonymous,
    dynamicId: dynamicId,
  );

  Future<LoadingState<VoteDraft>> load(Account account, int id) async {
    final result = await detail(account, id);
    return switch (result) {
      Success(:final response) => Success(
        VoteDraft(
          title: response.title!,
          description: response.desc ?? '',
          type:
              response.type ??
              (response.options.first.imgUrl?.isNotEmpty == true ? 1 : 0),
          choices: response.choiceCnt!,
          deadline: DateTime.fromMillisecondsSinceEpoch(
            response.endTime! * 1000,
          ),
          options: response.options
              .map(
                (item) => VoteOptionDraft(
                  text: item.optDesc ?? '',
                  image: item.imgUrl ?? '',
                ),
              )
              .toList(),
        ),
      ),
      Error error => error,
      _ => LoadingState.loading(),
    };
  }

  Future<LoadingState<VoteInfo>> save(
    Account account,
    int? id,
    VoteDraft draft,
  ) async {
    final info = VoteInfo(
      title: draft.title,
      desc: draft.description,
      type: draft.type,
      choiceCnt: draft.choices,
      duration: draft.deadline.difference(DateTime.now()).inSeconds,
      onlyFansLevel: 0,
      votePublisher: account.mid,
      voteId: id,
      options: [
        for (final option in draft.options)
          Option(optDesc: option.text, imgUrl: option.image),
      ],
    );
    final result = id == null
        ? await DynamicsHttp.createVote(info, account: account)
        : await DynamicsHttp.updateVote(info, account: account);
    return switch (result) {
      Success(:final response) => Success(info..voteId = response),
      Error error => error,
      _ => LoadingState.loading(),
    };
  }

  Future<LoadingState<String?>> upload(Account account, String path) async =>
      switch (await MsgHttp.uploadBfs(
        account: account,
        path: path,
        category: 'daily',
        biz: 'vote',
      )) {
        Success(:final response) => Success(response.imageUrl),
        Error error => error,
        _ => LoadingState.loading(),
      };
}
