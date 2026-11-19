import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/community/domain/article_collection/data.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

abstract final class ArticleRepository {
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
