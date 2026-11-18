import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/match.dart';
import 'package:pili_aurora_next/models/remote/match/match_info/contest.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:get/get.dart';

class MatchInfoController extends CommonDynController {
  MatchInfoController({int? oid})
    : oid = oid ?? int.tryParse(Get.parameters['cid'] ?? '') ?? 0;

  @override
  final int oid;
  @override
  final int replyType = 27;

  @override
  Object get sourceId => oid.toString();

  final Rx<LoadingState<MatchContest?>> infoState =
      LoadingState<MatchContest?>.loading().obs;
  int _infoVersion = 0;

  @override
  void onInit() {
    super.onInit();
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
      final res = await MatchHttp.matchInfo(oid, account: account);
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
  void onClose() {
    _infoVersion++;
    super.onClose();
  }
}
