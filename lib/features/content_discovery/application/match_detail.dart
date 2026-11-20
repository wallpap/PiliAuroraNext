import 'package:pili_aurora_next/features/community/application/content_page_detail.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/application/match_queries.dart';
import 'package:pili_aurora_next/models/remote/match/match_info/contest.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';

class MatchInfoController extends ContentPageDetail {
  MatchInfoController({required this.oid});

  @override
  final int oid;
  @override
  final int replyType = 27;

  @override
  Object get sourceId => oid.toString();

  final infoState = DetailValue(LoadingState<MatchContest?>.loading());
  int _infoVersion = 0;

  @override
  void open() {
    Accounts.mainChanges.addListener(_accountChanged);
    getMatchInfo();
  }

  void _accountChanged() {
    if (isClosed) return;
    infoState.value = LoadingState.loading();
    getMatchInfo();
  }

  Future<void> getMatchInfo() async {
    if (isClosed) return;
    if (oid <= 0) {
      infoState.value = const Error('赛事标识无效，请重新打开页面');
      commentSource.value = const Error('赛事标识无效，请重新打开页面');
      return;
    }
    if (commentSource.value is! Success) showComments();
    final version = ++_infoVersion;
    final account = Accounts.main;
    if (infoState.value is Error) infoState.value = LoadingState.loading();
    bool current() =>
        !isClosed &&
        version == _infoVersion &&
        identical(account, Accounts.main);
    try {
      final res = await MatchQueries.detail(account, oid);
      if (current()) infoState.value = res;
    } catch (error, stackTrace) {
      if (current()) infoState.value = Error.fromException(error, stackTrace);
    }
    if (!isClosed &&
        version == _infoVersion &&
        !identical(account, Accounts.main)) {
      infoState.value = const Error('账号已切换，请刷新赛事信息');
    }
  }

  @override
  Future<void> onReload() => getMatchInfo();

  @override
  void close() {
    if (isClosed) return;
    _infoVersion++;
    Accounts.mainChanges.removeListener(_accountChanged);
    infoState.dispose();
    super.close();
  }
}
