import 'package:pili_aurora_next/features/playback/data/video_metadata_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/video/video_stein_edgeinfo/data.dart';
import 'package:pili_aurora_next/services/logger.dart';

class VideoMetadata {
  int _edgeGeneration = 0;

  Future<EdgeInfoData?> interactiveEdge({
    required String bvid,
    required int? graphVersion,
    required bool Function() isCurrent,
    int? edgeId,
  }) async {
    final generation = ++_edgeGeneration;
    if (!isCurrent()) return null;
    try {
      final result = await VideoMetadataRepository.interactiveEdge(
        bvid: bvid,
        graphVersion: graphVersion,
        edgeId: edgeId,
      );
      if (!isCurrent() || generation != _edgeGeneration) return null;
      if (result.isSuccess) return result.data;
      logger.w('互动视频节点加载失败: $result');
    } catch (error, stackTrace) {
      logger.w('互动视频节点加载失败', error: error.runtimeType, stackTrace: stackTrace);
    }
    return null;
  }

  Future<LoadingState<List<double>>> danmakuTrend({
    required int aid,
    required String bvid,
    required int cid,
  }) async {
    try {
      return await VideoMetadataRepository.danmakuTrend(
        aid: aid,
        bvid: bvid,
        cid: cid,
      );
    } catch (error, stackTrace) {
      logger.w('弹幕趋势加载失败', error: error.runtimeType, stackTrace: stackTrace);
      return const Error(null);
    }
  }
}
