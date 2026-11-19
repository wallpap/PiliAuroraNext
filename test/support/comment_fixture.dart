import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/data/comments/comments_repository.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class CommentFixture extends CommentsRepository {
  final responses = Queue<FutureOr<LoadingState<Object>>>();
  final reads = <({Account account, int? anchor, int? dialog, Mode mode})>[];

  @override
  Future<LoadingState<MainListReply>> main(
    Account account,
    CommentTarget target,
    Mode mode,
    Int64? cursor,
    String? offset,
  ) async {
    reads.add((account: account, anchor: null, dialog: null, mode: mode));
    final result = await responses.removeFirst();
    return switch (result) {
      Success(response: MainListReply data) => Success(data),
      Error error => error,
      _ => throw StateError('Invalid main reply fixture'),
    };
  }

  @override
  Future<LoadingState<Object>> thread(
    Account account,
    CommentTarget target,
    int root,
    int? dialog,
    int? reply,
    Mode mode,
    String? offset,
  ) async {
    reads.add((account: account, anchor: reply, dialog: dialog, mode: mode));
    return await responses.removeFirst();
  }
}

CommentsQuery commentQuery({CommentThread? thread}) => (
  owner: Object(),
  target: (oid: 1, type: 1),
  thread: thread,
);

ProviderContainer commentContainer(CommentFixture fixture) =>
    ProviderContainer.test(
      overrides: [commentsRepositoryProvider.overrideWithValue(fixture)],
    );

Future<void> flushComments() => Future<void>.delayed(Duration.zero);
