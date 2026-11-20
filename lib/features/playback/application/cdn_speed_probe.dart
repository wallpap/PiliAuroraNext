import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/playback/data/video_media_repository.dart';
import 'package:pili_aurora_next/services/web_user_agent.dart';
import 'package:pili_aurora_next/common/service_urls.dart';
import 'package:pili_aurora_next/features/playback/domain/media/cdn_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/playback/application/media_source_selection.dart';

final class CdnSpeedProbe {
  CdnSpeedProbe({Dio? client}) : _client = client ?? Dio() {
    _client.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers.addAll({
        'user-agent': BrowserUa.pc,
        'referer': HttpString.baseUrl,
      });
  }

  final Dio _client;
  final _requests = <CancelToken>{};
  bool _closed = false;

  static Future<BaseItem> sample() async {
    final item = (await samples()).firstOrNull;
    if (item == null) throw const FormatException('响应缺少测速视频流');
    return item;
  }

  static Future<List<VideoItem>> samples() =>
      VideoMediaRepository.diagnosticsSample();

  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _requests) {
      request.cancel();
    }
    _requests.clear();
    _client.close(force: true);
  }

  Future<String?> measure(CDNService service, BaseItem video) async {
    if (_closed) return null;
    final token = CancelToken();
    _requests.add(token);
    final watch = Stopwatch()..start();
    var downloaded = 0;
    String? measured;
    String speed(int bytes) {
      final elapsed = watch.elapsedMicroseconds;
      return '${(bytes / (elapsed > 0 ? elapsed : 1)).toStringAsPrecision(3)}MB/s';
    }

    try {
      final url = MediaSourceSelection.getCdnUrl(
        video.playUrls,
        defaultCDNService: service,
      );
      final response = await _client.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: token,
        onReceiveProgress: (count, total) {
          downloaded = count;
          if (watch.elapsedMicroseconds >= 15000000 ||
              count >= 8 * 1024 * 1024) {
            if (count > 0) measured = speed(count);
            token.cancel();
          }
        },
      );
      downloaded = response.data?.length ?? downloaded;
      if (measured != null) return measured;
      if (downloaded <= 0) throw const FormatException('测速响应为空');
      return speed(downloaded);
    } catch (error, stack) {
      if (_closed) return null;
      if (measured != null) return measured;
      logger
          .scoped('cdnProbe')
          .w(
            'CDN 测速失败',
            error: error.runtimeType,
            stackTrace: stack,
          );
      return switch (error) {
        DioException(response: Response(statusCode: final int code))
            when code >= 400 && code < 500 =>
          '此视频可能无法替换为该CDN',
        DioException(
          type: DioExceptionType.connectionTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout,
        ) ||
        TimeoutException() => '测速超时，请重试',
        _ => '测速失败，请重试',
      };
    } finally {
      watch.stop();
      _requests.remove(token);
      token.cancel();
    }
  }
}
