import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_condition/data.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_result/data.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_index_result/list.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_timeline/pgc_timeline.dart';
import 'package:pili_aurora_next/models/remote/pgc/season_follow_status.dart';
import 'package:pili_aurora_next/models/remote/pgc/pgc_timeline/result.dart';
import 'package:dio/dio.dart';

abstract final class PgcHttp {
  static bool _validId(Object? id) => switch (id) {
    int value => value > 0,
    String value => (int.tryParse(value) ?? 0) > 0,
    _ => false,
  };

  static Future<LoadingState<PgcIndexResult>> pgcIndexResult({
    required Account account,
    required int page,
    required Map<String, dynamic> params,
    int? seasonType,
    int? type,
    int? indexType,
  }) async {
    return await Request().requestApi(
      Api.pgcIndexResult,
      kind: ApiCallKind.query,
      decode: (body) => PgcIndexResult.fromJson(body['data']),
      options: Options(extra: {'account': account}),
      queryParameters: {
        ...params,
        'season_type': ?seasonType,
        'type': ?type,
        'index_type': ?indexType,
        'page': page,
        'pagesize': 21,
      },
    );
  }

  static Future<LoadingState<PgcIndexConditionData>> pgcIndexCondition({
    required Account account,
    int? seasonType,
    required int type,
    int? indexType,
  }) async {
    return await Request().requestApi(
      Api.pgcIndexCondition,
      kind: ApiCallKind.query,
      decode: (body) => PgcIndexConditionData.fromJson(body['data']),
      options: Options(extra: {'account': account}),
      queryParameters: {
        'season_type': ?seasonType,
        'type': type,
        'index_type': ?indexType,
      },
    );
  }

  static Future<LoadingState<List<PgcIndexItem>?>> pgcIndex({
    int? page,
    int? indexType,
    Account? account,
  }) async {
    return await Request().requestApi(
      Api.pgcIndexResult,
      kind: ApiCallKind.query,
      decode: (body) => PgcIndexResult.fromJson(body['data']).list,
      options: Options(extra: {'account': account}),
      queryParameters: {
        'st': 1,
        'order': 3,
        'season_version': -1,
        'spoken_language_type': -1,
        'area': -1,
        'is_finish': -1,
        'copyright': -1,
        'season_status': -1,
        'season_month': -1,
        'year': -1,
        'style_id': -1,
        'sort': 0,
        'season_type': 1,
        'pagesize': 20,
        'type': 1,
        'page': page,
        'index_type': ?indexType,
      },
    );
  }

  static Future<LoadingState<List<TimelineResult>?>> pgcTimeline({
    int types = 1, // 1：`番剧`<br />3：`电影`<br />4：`国创` |
    required int before,
    required int after,
    Account? account,
  }) async {
    return await Request().requestApi(
      Api.pgcTimeline,
      kind: ApiCallKind.query,
      decode: (body) => PgcTimeline.fromJson(body).result,
      options: Options(extra: {'account': account}),
      queryParameters: {
        'types': types,
        'before': before,
        'after': after,
      },
    );
  }

  static Future<LoadingState<SeasonFollowStatus>> seasonStatus(
    Object? seasonId, {
    Account? account,
  }) async {
    if (!_validId(seasonId)) return const Error('番剧标识无效，请重新打开页面');
    return await Request().requestApi(
      Api.seasonStatus,
      kind: ApiCallKind.query,
      decode: (body) => SeasonFollowStatus.fromJson(body['result']),
      options: Options(extra: {'account': account}),
      queryParameters: {'season_id': seasonId},
    );
  }
}
