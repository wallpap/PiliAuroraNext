import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/account/data/account_manager/account_mgr.dart';
import 'package:pili_aurora_next/http/request_failure_policy.dart';
import 'package:pili_aurora_next/services/diagnostics/redact.dart';

void showRequestFailure(DioException error) {
  if (isExpectedHttpFailure(error)) return;
  final url = DiagnosticRedactor.text(error.requestOptions.uri);
  final status = error.response?.statusCode;
  AccountManager.dioError(error).then(
    (message) => SmartDialog.showToast(
      '$message\n${error.requestOptions.method} $url'
      '${status == null ? '' : ' (HTTP $status)'}',
    ),
  );
}
