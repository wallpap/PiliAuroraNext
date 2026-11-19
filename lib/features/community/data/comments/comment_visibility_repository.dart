import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/reply.dart';
import 'package:pili_aurora_next/models/common/reply/reply_sort_type.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef VisibilityPage = ({List<int?> ids, int? count, int? size});

abstract final class CommentVisibilityRepository {
  static Future<LoadingState<bool>> inPublicList({
    required int oid,
    required int type,
    required int id,
  }) async {
    final result = await ReplyHttp.replyList(
      isLogin: false,
      oid: oid,
      nextOffset: '',
      type: type,
      sort: ReplySortType.time.index,
      page: 1,
    );
    return switch (result) {
      Success(:final response) => Success(
        response.replies?.any((reply) => reply.rpid == id) ?? false,
      ),
      Error error => error,
      Loading loading => loading,
    };
  }

  static Future<LoadingState<VisibilityPage>> thread({
    required Account account,
    required bool isLogin,
    required int oid,
    required int type,
    required int root,
    required int page,
  }) async {
    final result = await ReplyHttp.replyReplyList(
      account: account,
      isLogin: isLogin,
      oid: oid,
      type: type,
      root: root,
      pageNum: page,
    );
    return switch (result) {
      Success(:final response) => Success((
        ids: response.replies?.map((reply) => reply.rpid).toList() ?? const [],
        count: response.page?.count,
        size: response.page?.size,
      )),
      Error error => error,
      Loading loading => loading,
    };
  }
}
