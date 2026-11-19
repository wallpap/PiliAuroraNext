import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/services/web_user_agent.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/remote/video/video_pbp/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_stein_edgeinfo/data.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

abstract final class VideoMetadataRepository {
  static Future<LoadingState<bool>> seasonSubscription(
    Account account,
    String bvid,
  ) async =>
      switch (await VideoHttp.videoRelation(bvid: bvid, account: account)) {
        Success(:final response) when response.seasonFav != null => Success(
          response.seasonFav!,
        ),
        Error error => error,
        _ => const Error('订阅状态未加载，请重试'),
      };

  static Future<LoadingState<Map<String, dynamic>>> staffRelations(
    Account account,
    Iterable<Object?> mids,
  ) => Request().requestApi(
    Api.relations,
    kind: ApiCallKind.query,
    options: Options(extra: {'account': account}),
    queryParameters: {'fids': mids.join(',')},
    decode: (body) => body['data'] as Map<String, dynamic>,
  );

  static Future<LoadingState<EdgeInfoData>> interactiveEdge({
    required String bvid,
    required int? graphVersion,
    int? edgeId,
  }) => Request().requestApi(
    '/x/stein/edgeinfo_v2',
    kind: ApiCallKind.query,
    queryParameters: {
      'bvid': bvid,
      'graph_version': graphVersion,
      'edge_id': ?edgeId,
    },
    decode: (body) => EdgeInfoData.fromJson(body['data']),
  );

  static Future<LoadingState<List<double>>> danmakuTrend({
    required int aid,
    required String bvid,
    required int cid,
  }) async {
    final response = await Request().get(
      'https://bvc.bilivideo.com/pbp/data',
      queryParameters: {'aid': aid, 'bvid': bvid, 'cid': cid, 'r': 'loader'},
      options: Options(
        headers: {
          'user-agent': BrowserUa.pc,
          'origin': 'https://www.bilibili.com',
          'referer': 'https://www.bilibili.com/video/$bvid',
        },
      ),
    );
    final payload = response.data;
    final modules = payload['modules'];
    final module = modules is List ? modules.firstOrNull : null;
    final params = module is Map ? module['params'] : null;
    final data = PbpData.fromJson(
      params is Map ? params['data'] ?? payload : payload,
    );
    final events = data.events?.eDefault;
    if ((data.stepSec ?? 0) == 0 || events == null || events.isEmpty) {
      return const Error(null);
    }
    return Success(List.unmodifiable(events));
  }
}
