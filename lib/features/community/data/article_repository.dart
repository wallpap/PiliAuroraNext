import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/community/domain/article_collection/data.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart';
import 'package:pili_aurora_next/features/community/domain/article/article_info/data.dart';
import 'package:pili_aurora_next/features/community/domain/article/article_view/data.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class ArticleRepository {
  static Future<LoadingState<DynamicItemModel>> opus(
    Account account,
    String id,
  ) => DynamicsHttp.opusDetail(account: account, opusId: id);

  static Future<LoadingState<ArticleViewData>> read(Account account, int id) =>
      DynamicsHttp.articleView(account: account, cvId: id);

  static Future<LoadingState<ArticleInfoData>> stats(Account account, int id) =>
      DynamicsHttp.articleInfo(account: account, cvId: id);

  static Future<LoadingState<void>> recordView(Account account, int id) =>
      VideoHttp.historyReport(account: account, aid: id, type: 5);

  static Future<LoadingState<ArticleCollection>> collection(
    Account account,
    String id,
  ) => Request().requestApi(
    Api.articleList,
    kind: ApiCallKind.query,
    decode: (body) => ArticleCollection.fromJson(body['data']),
    options: Options(extra: {'account': account}),
    queryParameters: {'id': id, 'web_location': 333.1400},
  );
}
