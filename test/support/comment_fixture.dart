import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/data/comments/comments_repository.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/reply/reply_sort_type.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class CommentFixture extends CommentsRepository {
  final responses = Queue<FutureOr<LoadingState<Object>>>();
  final reads =
      <({Account account, int? anchor, int? dialog, ReplySortType sort})>[];

  @override
  Future<LoadingState<CommentPage>> main(
    Account account,
    CommentTarget target,
    ReplySortType sort,
    Int64? cursor,
    String? offset,
  ) async {
    reads.add((account: account, anchor: null, dialog: null, sort: sort));
    final result = await responses.removeFirst();
    return switch (result) {
      Success(response: MainListReply data) => Success(mainCommentPage(data)),
      Error error => error,
      _ => throw StateError('Invalid main reply fixture'),
    };
  }

  @override
  Future<LoadingState<CommentPage>> thread(
    Account account,
    CommentTarget target,
    int root,
    int? dialog,
    int? reply,
    ReplySortType sort,
    String? offset,
  ) async {
    reads.add((account: account, anchor: reply, dialog: dialog, sort: sort));
    final result = await responses.removeFirst();
    return switch (result) {
      Success(response: DetailListReply data) => Success(
        detailCommentPage(data),
      ),
      Success(response: DialogListReply data) => Success(
        dialogCommentPage(data),
      ),
      Error error => error,
      _ => throw StateError('Invalid thread reply fixture'),
    };
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
