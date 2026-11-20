import 'package:pili_aurora_next/features/playback/domain/danmaku_block_rule.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_block_type.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:dio/dio.dart';

typedef DanmakuBlockListing = ({
  List<List<SimpleRule>> rules,
  String? notice,
});

abstract final class DanmakuBlockRepository {
  static Future<LoadingState<DanmakuBlockListing>> danmakuFilter({
    required Account account,
  }) async {
    return await Request().requestApi(
      Api.danmakuFilter,
      kind: ApiCallKind.query,
      decode: (body) {
        final data = body['data'] as Map<String, dynamic>;
        final items = data['rule'];
        if (items != null && items is! List) {
          throw const FormatException('屏蔽规则列表格式无效');
        }
        final grouped = [for (final _ in DmBlockType.values) <SimpleRule>[]];
        for (final item in items as List? ?? const []) {
          final rule = _decodeRule(item as Map<String, dynamic>);
          if (rule.type >= 0 && rule.type < grouped.length) {
            grouped[rule.type].add(rule);
          }
        }
        final notice = data['toast'] as String?;
        return (
          rules: List<List<SimpleRule>>.unmodifiable(
            grouped.map(List<SimpleRule>.unmodifiable),
          ),
          notice: notice == '' ? null : notice,
        );
      },
      options: Options(extra: {'account': account}),
    );
  }

  static Future<LoadingState<void>> danmakuFilterDel({
    required int ids,
    required Account account,
  }) async {
    return await Request().requestApi<void>(
      Api.danmakuFilterDel,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {
        'ids': ids,
        'csrf': account.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account, 'noRetry': true},
      ),
    );
  }

  static Future<LoadingState<SimpleRule>> danmakuFilterAdd({
    required String filter,
    required int type,
    required Account account,
  }) async {
    return await Request().requestApi(
      Api.danmakuFilterAdd,
      kind: ApiCallKind.mutation,
      decode: (body) {
        final rule = _decodeRule(body['data'] as Map<String, dynamic>);
        if (rule.id <= 0 || rule.type != type) {
          throw const FormatException('新增规则响应的 ID 或类型无效');
        }
        return rule;
      },
      data: {
        'type': type,
        'filter': filter,
        'csrf': account.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account, 'noRetry': true},
      ),
    );
  }

  static SimpleRule _decodeRule(Map<String, dynamic> json) => SimpleRule(
    id: json['id'] as int,
    type: json['type'] as int,
    filter: json['filter'] as String,
  );
}
