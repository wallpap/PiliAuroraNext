import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/features/playback/domain/subtitle_format.dart';
import 'package:pili_aurora_next/grpc/dm.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/video/video_play_info/subtitle.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/extension/string_ext.dart';

abstract final class SubtitleRepository {
  static Future<LoadingState<List<Subtitle>>> publicTracks(
    int aid,
    int cid,
  ) async {
    final result = await DmGrpc.dmView(aid, cid);
    return switch (result) {
      Success(:final response) => Success(
        response.hasSubtitle()
            ? ([
                for (final item in response.subtitle.subtitles)
                  Subtitle(
                    lan: item.lan,
                    lanDoc: item.lanDoc,
                    subtitleUrl: item.subtitleUrl.replaceFirst(
                      RegExp('^https?:'),
                      '',
                    ),
                    isAi: item.type == .AI,
                  ),
              ]..sort())
            : const [],
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }

  static Future<LoadingState<String>> fetch(
    String subtitleUrl, {
    SubtitleFormat format = .vtt,
  }) async {
    final url = subtitleUrl.startsWith('//')
        ? 'https:$subtitleUrl'
        : subtitleUrl;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const Error('字幕地址无效，请重新选择');
    }
    Request();
    try {
      final response = await Request.dio.get<dynamic>(
        url,
        options: Options(extra: {'account': const NoAccount()}),
      );
      final data = response.data;
      final body = data is Map<String, dynamic> ? data['body'] : null;
      if (body is! List) throw const FormatException('字幕响应缺少正文列表');
      final subtitle = switch (format) {
        .json => jsonEncode(data),
        .vtt => await compute<List, String>(SubtitleUtils.json2Vtt, body),
        .srt => await compute<List, String>(SubtitleUtils.json2Srt, body),
      };
      return Success(subtitle);
    } on DioException catch (error, stackTrace) {
      return await decodeApiException(
        error,
        stackTrace,
        kind: ApiCallKind.query,
      );
    } catch (error, stackTrace) {
      return Error.fromException(error, stackTrace);
    }
  }

  static Future<Uint8List?> originalBytes(String url) async {
    final uri = Uri.tryParse(url.http2https);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('字幕地址无效，请重新选择');
    }
    Request();
    final response = await Request.dio.get<Uint8List>(
      uri.toString(),
      options: Options(
        responseType: .bytes,
        headers: Constants.baseHeaders,
        extra: {'account': const NoAccount()},
      ),
    );
    if (response.statusCode != 200 || response.data == null) return null;
    return Uint8List.fromList(
      Request.responseBytesDecoder(response.data!, response.headers.map),
    );
  }
}
