import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/grpc/reply.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/reply.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final commentsRepositoryProvider = Provider(
  (ref) => const CommentsRepository(),
);

class CommentsRepository {
  const CommentsRepository();

  Future<LoadingState<MainListReply>> main(
    Account account,
    ({int oid, int type}) target,
    Mode mode,
    Int64? cursor,
    String? offset,
  ) => ReplyGrpc.mainList(
    account: account,
    oid: target.oid,
    type: target.type,
    mode: mode,
    offset: offset,
    cursorNext: cursor,
  );

  Future<LoadingState<Object>> thread(
    Account account,
    ({int oid, int type}) target,
    int root,
    int? dialog,
    int? reply,
    Mode mode,
    String? offset,
  ) => dialog == null
      ? ReplyGrpc.detailList(
          account: account,
          oid: target.oid,
          type: target.type,
          root: root,
          rpid: reply ?? 0,
          mode: mode,
          offset: offset,
        )
      : ReplyGrpc.dialogList(
          account: account,
          oid: target.oid,
          type: target.type,
          root: root,
          dialog: dialog,
          offset: offset,
        );

  Future<LoadingState<void>> togglePinned(
    Account account,
    ({int oid, int type}) target,
    ReplyInfo item,
  ) => ReplyHttp.replyTop(
    account: account,
    oid: target.oid,
    type: target.type,
    rpid: item.id,
    isUpTop: item.replyControl.isUpTop,
  );
}
