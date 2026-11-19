import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/browser_ua.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/video/video_pbp/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_stein_edgeinfo/data.dart';

abstract final class VideoMetadataRepository {
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
