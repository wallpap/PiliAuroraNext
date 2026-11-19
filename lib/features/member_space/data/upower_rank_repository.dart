import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/member_space/domain/upower_ranking.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

abstract final class UpowerRankRepository {
  static Future<LoadingState<UpowerRanking>> load(
    Account account,
    Object mid, {
    int? privilege,
  }) => Request().requestApi(
    Api.upowerRank,
    kind: ApiCallKind.query,
    options: Options(extra: {'account': account}),
    queryParameters: {
      'up_mid': mid,
      'pn': 1,
      'ps': 100,
      'privilege_type': ?privilege,
      'mobi_app': 'web',
      'web_location': 333.1196,
      if (account.isLogin) 'csrf': account.csrf,
    },
    decode: (body) {
      final data = body['data'] as Map<String, dynamic>;
      final ranks = (data['rank_info'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final tiers = (data['level_info'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final levels = <UpowerRankLevel>[];
      final seen = <int?>{};
      for (final tier in tiers) {
        final id = tier['privilege_type'] as int?;
        if ((id == null && levels.isNotEmpty) || !seen.add(id)) continue;
        levels.add((
          privilegeType: id,
          name: tier['name'] as String?,
          memberTotal: tier['member_total'] as int?,
        ));
      }
      return UpowerRanking(
        ranks.map(
          (row) => (
            mid: row['mid'] as int?,
            nickname: row['nickname'] as String?,
            avatar: row['avatar'] as String?,
            day: row['day'] as int?,
          ),
        ),
        levels,
      );
    },
  );
}
