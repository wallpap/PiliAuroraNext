import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/playback/domain/seek_preview.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/browser_ua.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';

abstract final class SeekPreviewRepository {
  static Future<LoadingState<SeekPreviewAtlas>> fetch(
    SeekPreviewSource source, {
    CancelToken? cancelToken,
  }) async {
    final result = await Request().requestApi<SeekPreviewAtlas>(
      Api.videoshot,
      kind: ApiCallKind.query,
      cancelToken: cancelToken,
      queryParameters: {'bvid': source.bvid, 'cid': source.cid, 'index': 1},
      options: Options(
        headers: {
          'user-agent': BrowserUa.pc,
          'referer': 'https://www.bilibili.com/video/${source.bvid}',
        },
      ),
      decode: (body) {
        final json = body['data'] as Map<String, dynamic>;
        return SeekPreviewAtlas(
          columns: json['img_x_len'] as int,
          rows: json['img_y_len'] as int,
          images: (json['image'] as List).cast<String>().map(
            (image) => image.http2https,
          ),
          timestamps: (json['index'] as List).cast<int>(),
        );
      },
    );
    return switch (result) {
      Success(:final response) when !response.isAvailable => const Error(
        '暂无视频预览',
      ),
      _ => result,
    };
  }
}
