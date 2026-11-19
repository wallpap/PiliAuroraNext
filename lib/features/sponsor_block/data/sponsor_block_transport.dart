import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:pili_aurora_next/build_config.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/accounts/account_manager/account_mgr.dart';

/// 使用 HTTP 状态码的第三方协议，不套用 B 站 code/message/data 业务包体。
abstract final class SponsorBlockTransport {
  static Future<LoadingState<T>> request<T>(
    String server,
    String endpoint, {
    required ApiCallKind kind,
    required T Function(dynamic body) decode,
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    server = server.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(server);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return const Error('空降助手服务器地址无效，请检查设置');
    }
    final Response<dynamic> response;
    try {
      Request();
      response = await Request.dio.request<dynamic>(
        '$server/api/$endpoint',
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: kind == ApiCallKind.query ? 'GET' : 'POST',
          followRedirects: true,
          headers: kDebugMode
              ? null
              : {
                  'origin': Constants.appName,
                  'x-ext-version': BuildConfig.versionName,
                },
          // 自定义服务器不使用 B 站账号，且写入无论重试设置如何都不能重放。
          extra: {
            'account': const NoAccount(),
            'noRetry': kind == ApiCallKind.mutation,
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error, stackTrace) {
      final status = error.response?.statusCode;
      if (_isRejection(status)) {
        return _httpError(status, cause: error, stackTrace: stackTrace);
      }
      if (kind == ApiCallKind.mutation) {
        return UnknownResult(cause: error, stackTrace: stackTrace);
      }
      return Error(
        await AccountManager.dioError(error),
        code: status,
        cause: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      final failure = Error.fromException(error, stackTrace);
      return kind == ApiCallKind.mutation
          ? UnknownResult(cause: error, stackTrace: stackTrace)
          : failure;
    }
    if (response.statusCode != 200) {
      final failure = _httpError(response.statusCode);
      return kind == ApiCallKind.mutation && !_isRejection(response.statusCode)
          ? UnknownResult(cause: failure)
          : failure;
    }
    try {
      return Success(decode(response.data));
    } catch (error, stackTrace) {
      final failure = Error.fromException(error, stackTrace);
      return kind == ApiCallKind.mutation
          ? UnknownResult(cause: error, stackTrace: stackTrace)
          : failure;
    }
  }

  static bool _isRejection(int? status) =>
      status != null && status >= 400 && status < 500 && status != 408;

  static Error _httpError(
    int? status, {
    Object? cause,
    StackTrace? stackTrace,
  }) => Error(
    switch (status) {
      400 => '参数错误',
      403 => '被自动审核机制拒绝',
      404 => '未找到数据',
      409 => '重复提交',
      429 => '提交太快，请稍后再试',
      500 => '服务器无法获取信息',
      _ => status == null ? '未收到有效的服务器响应' : '服务器响应异常（HTTP $status）',
    },
    code: status,
    cause: cause,
    stackTrace: stackTrace,
  );
}
