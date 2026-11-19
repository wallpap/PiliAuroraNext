import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/grpc/reply.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/reply.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/common/reply/reply_sort_type.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final commentsRepositoryProvider = Provider(
  (ref) => const CommentsRepository(),
);

class CommentsRepository {
  const CommentsRepository();

  Future<LoadingState<CommentPage>> main(
    Account account,
    ({int oid, int type}) target,
    ReplySortType sort,
    Int64? cursor,
    String? offset,
  ) async => _map(
    await ReplyGrpc.mainList(
      account: account,
      oid: target.oid,
      type: target.type,
      mode: _mode(sort),
      offset: offset,
      cursorNext: cursor,
    ),
    mainCommentPage,
  );

  Future<LoadingState<CommentPage>> thread(
    Account account,
    ({int oid, int type}) target,
    int root,
    int? dialog,
    int? reply,
    ReplySortType sort,
    String? offset,
  ) async => dialog == null
      ? _map(
          await ReplyGrpc.detailList(
            account: account,
            oid: target.oid,
            type: target.type,
            root: root,
            rpid: reply ?? 0,
            mode: _mode(sort),
            offset: offset,
          ),
          detailCommentPage,
        )
      : _map(
          await ReplyGrpc.dialogList(
            account: account,
            oid: target.oid,
            type: target.type,
            root: root,
            dialog: dialog,
            offset: offset,
          ),
          dialogCommentPage,
        );

  static Mode _mode(ReplySortType sort) =>
      sort == ReplySortType.time ? .MAIN_LIST_TIME : .MAIN_LIST_HOT;

  static LoadingState<Output> _map<Input, Output>(
    LoadingState<Input> result,
    Output Function(Input) convert,
  ) => switch (result) {
    Success(:final response) => Success(convert(response)),
    Error error => error,
    Loading loading => loading,
  };

  Future<LoadingState<CommentContent?>> translate(
    Account account,
    CommentReply reply,
  ) async => _map(
    await ReplyGrpc.translateReply(
      account: account,
      type: reply.type,
      oid: reply.oid,
      rpid: reply.id,
    ),
    (response) {
      final item = response.translatedReplies[reply.id];
      return item == null || !item.hasTranslatedContent()
          ? null
          : commentContentFromProtocol(item.translatedContent);
    },
  );

  Future<LoadingState<CommentReply?>> publish({
    required Account account,
    required int type,
    required int oid,
    required String message,
    int? root,
    int? parent,
    List? pictures,
    bool syncToDynamic = false,
    Map<String, int>? atNameToMid,
  }) async => _map(
    await VideoHttp.replyAdd(
      account: account,
      type: type,
      oid: oid,
      message: message,
      root: root,
      parent: parent,
      pictures: pictures,
      syncToDynamic: syncToDynamic,
      atNameToMid: atNameToMid,
    ),
    (reply) => reply == null ? null : commentFromProtocol(reply),
  );

  Future<LoadingState<void>> togglePinned(
    Account account,
    ({int oid, int type}) target,
    CommentReply item,
  ) => ReplyHttp.replyTop(
    account: account,
    oid: target.oid,
    type: target.type,
    rpid: item.id,
    isUpTop: item.replyControl.isUpTop,
  );
}
