import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/live/live_contribution_rank_type.dart';
import 'package:pili_aurora_next/models/remote/live/live_contribution_rank/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_contribution_rank/item.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';

class ContributionRankController
    extends
        CommonListController<
          LiveContributionRankData,
          LiveContributionRankItem
        > {
  final Object ruid;
  final Object roomId;
  final LiveContributionRankType type;

  ContributionRankController({
    required this.ruid,
    required this.roomId,
    required this.type,
  });

  @override
  Object get queryContext => Accounts.main;

  @override
  void onInit() {
    super.onInit();
    Accounts.mainChanges.addListener(_onAccountChanged);
    queryData();
  }

  void _onAccountChanged() => onReload();

  @override
  List<LiveContributionRankItem>? getDataList(
    LiveContributionRankData response,
  ) {
    return response.item;
  }

  @override
  Future<LoadingState<LiveContributionRankData>> customGetData() =>
      LiveHttp.liveContributionRank(
        ruid: ruid,
        roomId: roomId,
        page: page,
        type: type,
      );

  @override
  void onClose() {
    Accounts.mainChanges.removeListener(_onAccountChanged);
    super.onClose();
  }
}
