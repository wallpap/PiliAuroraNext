import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/pages/common/discovery_list_controller.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class HotController
    extends
        DiscoveryListController<List<HotVideoItemModel>, HotVideoItemModel> {
  @override
  Account get queryAccount => Accounts.get(AccountType.recommend);

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState<List<HotVideoItemModel>>> customGetData() =>
      VideoHttp.hotVideoList(
        pn: page,
        ps: 20,
      );
}
