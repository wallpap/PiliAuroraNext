import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/reply/data.dart';
import 'package:pili_aurora_next/models/remote/reply2reply/data.dart';
import 'package:pili_aurora_next/models/remote/reply_interaction/data.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/data/account_manager/account_mgr.dart';
import 'package:dio/dio.dart';

abstract final class ReplyHttp {
  static final Options options = Options(
    headers: {...Constants.baseHeaders, 'cookie': ''},
    extra: {'account': const NoAccount()},
  );

  static Future<LoadingState<ReplyData>> replyList({
    Account? account,
    required bool isLogin,
    required int oid,
    required String nextOffset,
    required int type,
    required int page,
    int sort = 1,
  }) {
    return Request().requestApi(
      isLogin ? Api.replyList : '${Api.replyList}/main',
      kind: ApiCallKind.query,
      decode: (body) => ReplyData.fromJson(body['data']),
      queryParameters: {
        'oid': oid,
        'type': type,
        if (isLogin) ...{
          'sort': sort,
          'pn': page,
          'ps': 20,
        } else ...{
          'pagination_str': '{"offset":"${nextOffset.replaceAll('"', '\\"')}"}',
          'mode': sort + 2, // 2：按时间排序；3：按热度排序
        },
      },
      options: isLogin
          ? Options(
              extra: {
                'account':
                    account ?? AccountManager.resolveAccount(Api.replyList),
              },
            )
          : options,
    );
  }

  static Future<LoadingState<ReplyReplyData>> replyReplyList({
    Account? account,
    required bool isLogin,
    required int oid,
    required int root,
    required int pageNum,
    required int type,
  }) {
    account ??= AccountManager.resolveAccount(Api.replyReplyList);
    return Request().requestApi(
      Api.replyReplyList,
      kind: ApiCallKind.query,
      decode: (body) => ReplyReplyData.fromJson(body['data']),
      queryParameters: {
        'oid': oid,
        'root': root,
        'pn': pageNum,
        'type': type,
        'sort': 1,
        if (isLogin) 'csrf': account.csrf,
      },
      options: isLogin ? Options(extra: {'account': account}) : options,
    );
  }

  static Future<LoadingState<void>> hateReply({
    Account? account,
    required int type,
    required int action,
    required int oid,
    required int rpid,
  }) {
    account ??= Accounts.main;
    return Request().requestApi<void>(
      Api.hateReply,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {
        'type': type,
        'oid': oid,
        'rpid': rpid,
        'action': action,
        'csrf': account.csrf,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  // 评论点赞
  static Future<LoadingState<void>> likeReply({
    Account? account,
    required int type,
    required int oid,
    required int rpid,
    required int action,
  }) {
    account ??= Accounts.main;
    return Request().requestApi<void>(
      Api.likeReply,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {
        'type': type,
        'oid': oid,
        'rpid': rpid,
        'action': action,
        'csrf': account.csrf,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  static Future<LoadingState<void>> replyTop({
    Account? account,
    required Object oid,
    required Object type,
    required Object rpid,
    required bool isUpTop,
  }) {
    account ??= Accounts.main;
    return Request().requestApi<void>(
      Api.replyTop,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {
        'oid': oid,
        'type': type,
        'rpid': rpid,
        'action': isUpTop ? 0 : 1,
        'csrf': account.csrf,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  static Future<LoadingState<void>> report({
    Account? account,
    required Object rpid,
    required Object oid,
    required int reasonType,
    bool banUid = true,
    String? reasonDesc,
  }) {
    account ??= Accounts.main;
    return Request().requestApi<void>(
      Api.replyReport,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {
        'add_blacklist': banUid,
        'csrf': account.csrf,
        'gaia_source': 'main_h5',
        'oid': oid,
        'platform': 'android',
        'reason': reasonType,
        'rpid': rpid,
        'scene': 'main',
        'type': 1,
        'content': ?reasonDesc,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  static Future<LoadingState<ReplyInteractData>> replyInteraction({
    Account? account,
    required Object oid,
    required Object type,
  }) {
    return Request().requestApi(
      Api.replyInteraction,
      kind: ApiCallKind.query,
      decode: (body) => ReplyInteractData.fromJson(body['data']),
      queryParameters: {
        'oid': oid,
        'type': type,
        'web_location': 333.1369,
      },
      options: Options(extra: {'account': account ?? Accounts.main}),
    );
  }

  static Future<LoadingState<String?>> replySubjectModify({
    Account? account,
    required int oid,
    required int type,
    required int action,
  }) {
    account ??= Accounts.main;
    return Request().requestApi(
      Api.replySubjectModify,
      kind: ApiCallKind.mutation,
      decode: (body) => body['data']?['action_toast'] as String?,
      data: {
        'oid': oid,
        'type': type,
        'action': action,
        'csrf': account.csrf,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }
}
