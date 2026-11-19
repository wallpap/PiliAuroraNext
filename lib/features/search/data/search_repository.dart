import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/http/validate.dart';
import 'package:pili_aurora_next/models/common/search/search_type.dart';
import 'package:pili_aurora_next/models/login/gaia_result.dart';
import 'package:pili_aurora_next/models/remote/search/search_rcmd/data.dart';
import 'package:pili_aurora_next/models/remote/search/search_trending/data.dart';
import 'package:pili_aurora_next/models/search/result.dart';
import 'package:pili_aurora_next/models/search/suggest.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/wbi_sign.dart';

class SearchRepository {
  const SearchRepository();

  Future<String?> defaultKeyword() async {
    final response = await Request().get(
      Api.searchDefault,
      queryParameters: await WbiSign.makSign({'web_location': 333.1365}),
    );
    if (response.data['code'] != 0) return null;
    return response.data['data']?['name'] as String? ?? '';
  }

  Future<LoadingState<SearchSuggestModel>> suggest(
    Account account,
    String term,
  ) => SearchHttp.searchSuggest(term: term, account: account);

  Future<LoadingState<SearchTrendingData>> trending({
    int limit = 30,
    bool needsTop = false,
  }) => SearchHttp.searchTrending(limit: limit, needsTop: needsTop);

  Future<LoadingState<SearchRcmdData>> recommendations() =>
      SearchHttp.searchRecommend();

  Future<LoadingState<SearchNumData>> results({
    required Account account,
    required SearchType type,
    required String keyword,
    required int page,
    required Map<String, dynamic> filters,
    String? verificationToken,
  }) => SearchHttp.searchByType<SearchNumData>(
    account: account,
    searchType: type,
    keyword: keyword,
    page: page,
    order: filters['order'],
    duration: filters['duration'],
    tids: filters['tids'],
    orderSort: filters['orderSort'],
    userType: filters['userType'],
    categoryId: filters['categoryId'],
    pubBegin: filters['pubBegin'],
    pubEnd: filters['pubEnd'],
    gaiaVtoken: verificationToken,
  );

  Future<LoadingState<GaiaChallenge>> registerChallenge(
    Account account,
    String voucher,
  ) => ValidateHttp.gaiaVgateRegister(voucher, account: account);

  Future<LoadingState<GaiaVerificationResult>> submitChallenge({
    required Account account,
    required String challenge,
    required String seccode,
    required String token,
    required String validate,
  }) => ValidateHttp.gaiaVgateValidate(
    account: account,
    challenge: challenge,
    seccode: seccode,
    token: token,
    validate: validate,
  );
}
