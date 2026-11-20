import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/match.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/match/match_info/contest.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class MatchQueries {
  static Future<LoadingState<MatchContest?>> detail(Account account, int id) {
    if (id <= 0) return Future.value(const Error('赛事标识无效，请重新打开页面'));
    return MatchHttp.matchInfo(id, account: account);
  }
}
