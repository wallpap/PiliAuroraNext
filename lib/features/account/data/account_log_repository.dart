import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/account/domain/account_log.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class AccountLogRepository {
  static Future<LoadingState<List<LogRow>>> load(
    Account account,
    LogType type,
  ) => Request().requestApi(
    switch (type) {
      .login => Api.loginLog,
      .coin => Api.coinLog,
      .exp => Api.expLog,
    },
    kind: ApiCallKind.query,
    options: Options(extra: {'account': account}),
    queryParameters: const {'jsonp': 'jsonp', 'web_location': '333.33'},
    decode: (body) {
      final data = body['data'] as Map<String, dynamic>;
      final rows = data['list'] as List<dynamic>? ?? const [];
      return List<LogRow>.unmodifiable(
        rows.cast<Map<String, dynamic>>().map(
          (row) => type == .login
              ? type.row(
                  row['time_at'] as String? ?? '',
                  row['ip'] as String? ?? '',
                  row['geo'] as String? ?? '',
                )
              : type.row(
                  row['time'] as String,
                  (row['delta'] as num).toString(),
                  row['reason'] as String,
                ),
        ),
      );
    },
  );
}
