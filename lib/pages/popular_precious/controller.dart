import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/models/remote/popular/popular_precious/data.dart';
import 'package:pili_aurora_next/pages/common/discovery_list_controller.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class PopularPreciousController
    extends DiscoveryListController<PopularPreciousData, HotVideoItemModel> {
  @override
  Account get queryAccount => Accounts.get(AccountType.recommend);

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  int? mediaId;

  @override
  List<HotVideoItemModel>? getDataList(PopularPreciousData response) {
    mediaId = response.mediaId;
    return response.list;
  }

  @override
  Future<LoadingState<PopularPreciousData>> customGetData() =>
      VideoHttp.popularPrecious(page: page);
}
