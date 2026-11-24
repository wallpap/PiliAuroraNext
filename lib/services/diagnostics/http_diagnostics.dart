import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/request_failure_policy.dart';
import 'package:pili_aurora_next/http/response_transformer.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';

class DiagnosticHttpInterceptor extends Interceptor {
  DiagnosticHttpInterceptor({Diagnostics? diagnostics})
    : _diagnostics = diagnostics ?? Diagnostics.instance;

  final Diagnostics _diagnostics;
  static const _key = 'piliDiagnosticOperation';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 重试可能复用 RequestOptions；先结束上一轮，避免活动请求计数泄漏。
    (options.extra.remove(_key) as TraceOperation?)?.finish(
      error: 'retry',
      errorLevel: DiagnosticLogLevel.debug,
    );
    CompressedResponseTransformer.setDecodeSampling(
      options,
      enabled: _diagnostics.accepts(DiagnosticLogLevel.debug),
    );
    options.extra[_key] = _diagnostics.begin(
      'http',
      options.method,
      details: {
        'host': options.uri.host,
        // 不记录查询参数、请求头、请求体或响应体。
        'path': options.uri.path,
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final decode = CompressedResponseTransformer.takeDecodeSample(
      response.requestOptions,
    );
    (response.requestOptions.extra.remove(_key) as TraceOperation?)?.finish(
      details: {
        'status': response.statusCode,
        'declaredResponseBytes': int.tryParse(
          response.headers.value('content-length') ?? '',
        ),
        ...?decode,
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    CompressedResponseTransformer.takeDecodeSample(err.requestOptions);
    final level = isExpectedHttpFailure(err)
        ? DiagnosticLogLevel.debug
        : DiagnosticLogLevel.error;
    final operation = err.requestOptions.extra.remove(_key) as TraceOperation?;
    operation?.finish(
      errorLevel: level,
      error: err.type.name,
      stack: err.stackTrace,
      details: {'status': err.response?.statusCode},
    );
    if (operation == null) {
      _diagnostics.log(
        level,
        'http',
        '请求失败',
        stack: err.stackTrace,
        details: {
          'host': err.requestOptions.uri.host,
          'path': err.requestOptions.uri.path,
          'method': err.requestOptions.method,
          'type': err.type.name,
          'status': err.response?.statusCode,
        },
      );
    }
    handler.next(err);
  }
}
