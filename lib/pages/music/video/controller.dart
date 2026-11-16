import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/music.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_detail.dart';
import 'package:pili_aurora_next/models/remote/music/bgm_recommend_list.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:get/get.dart';

typedef MusicRecommendArgs = ({String id, MusicDetail item});

class MusicRecommendController
    extends CommonListController<List<BgmRecommend>?, BgmRecommend> {
  late final String musicId;
  late final MusicDetail musicDetail;

  @override
  Object get queryContext => Accounts.get(AccountType.recommend);

  @override
  void onInit() {
    super.onInit();
    final MusicRecommendArgs args = Get.arguments;
    musicId = args.id;
    musicDetail = args.item;
    queryData();
  }

  @override
  void checkIsEnd(int length) {
    isEnd = true;
  }

  @override
  Future<LoadingState<List<BgmRecommend>?>> customGetData() =>
      MusicHttp.bgmRecommend(musicId);
}
