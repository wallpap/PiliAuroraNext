import 'package:pili_aurora_next/features/subscriptions/data/subscription_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_detail.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_video.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:get/get.dart';

class SubDetailController
    extends CommonListController<SubDetailData, SubDetailItemModel> {
  final _repository = SubscriptionRepository();
  late int id;
  String? heroTag;
  SubItemModel? subInfo;

  @override
  Object get queryContext => Accounts.main;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    id = args['id'];
    subInfo = args['subInfo'];
    heroTag = args['heroTag'];

    Accounts.mainChanges.addListener(_onAccountChanged);
    queryData();
  }

  void _onAccountChanged() {
    subInfo = null;
    onReload();
  }

  @override
  void onClose() {
    Accounts.mainChanges.removeListener(_onAccountChanged);
    super.onClose();
  }

  @override
  int remainingItemsToLoad(int remaining) =>
      _repository.hideInvalid &&
          !isEnd &&
          loadingState.value.dataOrNull?.isEmpty == true
      ? 1
      : 0;

  @override
  List<SubDetailItemModel>? getDataList(SubDetailData response) {
    subInfo = response.info;
    final count = subInfo?.mediaCount;
    if ((response.medias?.length ?? 0) < 20 ||
        (count != null && page * 20 >= count)) {
      isEnd = true;
    }
    return response.medias;
  }

  @override
  void handleListResponse(List<SubDetailItemModel> dataList) {
    if (!_repository.hideInvalid) return;
    final hidden = _repository.hidden(Accounts.main).read(21, id);
    dataList.removeWhere((item) => hidden.contains('2:${item.id}'));
  }

  @override
  void checkIsEnd(int length) {
    final count = subInfo?.mediaCount;
    if (count != null && length >= count) {
      isEnd = true;
    }
  }

  @override
  Future<LoadingState<SubDetailData>> customGetData() =>
      _repository.detail(Accounts.main, id, page);
}
