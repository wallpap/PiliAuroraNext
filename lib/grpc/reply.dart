import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/features/community/data/content_filter_preferences.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/generated/bilibili/pagination.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/grpc/url.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:fixnum/fixnum.dart';

abstract final class ReplyGrpc {
  // static Future replyInfo({required int rpid}) {
  //   return _request(
  //     GrpcUrl.replyInfo,
  //     ReplyInfoReq(rpid: Int64(rpid)),
  //     ReplyInfoReply.fromBuffer,
  //     onSuccess: (response) => response.reply,
  //   );
  // }

  // ref BiliRoamingX
  static bool _hasGoods(ReplyInfo reply) {
    return (reply.content.urls.isNotEmpty &&
            reply.content.urls.values.any((url) {
              return url.hasExtra() &&
                  (url.extra.goodsCmControl == Int64.ONE ||
                      url.extra.hasGoodsItemId() ||
                      url.extra.hasGoodsPrefetchedCache());
            })) ||
        reply.content.message.contains(Constants.goodsUrlPrefix);
  }

  static bool Function(ReplyInfo) _commentFilter() {
    final (:keywords, :hideGoods) = ContentFilterPreferences.comments();
    return (reply) =>
        keywords?.hasMatch(reply.content.message) == true ||
        (hideGoods && _hasGoods(reply));
  }

  static Future<LoadingState<MainListReply>> mainList({
    Account? account,
    int type = 1,
    required int oid,
    required Mode mode,
    required String? offset,
    required Int64? cursorNext,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.mainList,
      MainListReq(
        oid: Int64(oid),
        type: Int64(type),
        rpid: Int64.ZERO,
        cursor: CursorReq(
          mode: mode,
          next: cursorNext,
        ),
        // mode: mode,
        // pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      MainListReply.fromBuffer,
      kind: .query,
      account: account ?? Accounts.main,
    );
    if (res case Success(:final response)) {
      final needRemoveGrpc = _commentFilter();
      // keyword filter
      if (response.hasUpTop()) {
        if (needRemoveGrpc(response.upTop)) {
          response.clearUpTop();
        } else {
          response.upTop.replies.removeWhere(needRemoveGrpc);
        }
      }

      if (response.replies.isNotEmpty) {
        response.replies.removeWhere((item) {
          final hasMatch = needRemoveGrpc(item);
          if (!hasMatch && item.replies.isNotEmpty) {
            item.replies.removeWhere(needRemoveGrpc);
          }
          return hasMatch;
        });
      }
    }
    return res;
  }

  static Future<LoadingState<DetailListReply>> detailList({
    Account? account,
    int type = 1,
    required int oid,
    required int root,
    required int rpid,
    required Mode mode,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.detailList,
      DetailListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        rpid: Int64(rpid),
        scene: DetailListScene.REPLY,
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DetailListReply.fromBuffer,
      kind: .query,
      account: account ?? Accounts.main,
    );
    return res..dataOrNull?.root.replies.removeWhere(_commentFilter());
  }

  static Future<LoadingState<DialogListReply>> dialogList({
    Account? account,
    int type = 1,
    required int oid,
    required int root,
    required int dialog,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.dialogList,
      DialogListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        dialog: Int64(dialog),
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DialogListReply.fromBuffer,
      kind: .query,
      account: account ?? Accounts.main,
    );
    return res..dataOrNull?.replies.removeWhere(_commentFilter());
  }

  static Future<LoadingState<SearchItemReply>> searchItem({
    Account? account,
    required int page,
    required SearchItemType itemType,
    required int oid,
    int type = 1,
    String? keyword,
  }) {
    return GrpcReq.request(
      GrpcUrl.searchItem,
      SearchItemReq(
        cursor: SearchItemCursorReq(
          next: Int64(page),
          itemType: itemType,
        ),
        oid: Int64(oid),
        type: Int64(type),
        keyword: keyword,
      ),
      SearchItemReply.fromBuffer,
      kind: .query,
      account: account ?? Accounts.main,
    );
  }

  static Future<LoadingState<TranslateReplyResp>> translateReply({
    Account? account,
    required Int64 type,
    required Int64 oid,
    required Int64 rpid,
  }) {
    return GrpcReq.request(
      GrpcUrl.translateReply,
      TranslateReplyReq(
        type: type,
        oid: oid,
        rpids: [rpid],
      ),
      TranslateReplyResp.fromBuffer,
      kind: .query,
      account: account ?? Accounts.main,
    );
  }
}
