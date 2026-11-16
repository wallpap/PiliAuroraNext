import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart'
    show SearchItemReply, SearchItem, SearchItemType;
import 'package:pili_aurora_next/grpc/reply.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/reply/reply_search_type.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';
import 'package:pili_aurora_next/pages/video/reply_search_item/controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';

class ReplySearchChildController
    extends CommonListController<SearchItemReply, SearchItem> {
  ReplySearchChildController(this.controller, this.searchType);

  final ReplySearchController controller;
  final ReplySearchType searchType;

  @override
  Object get queryContext => Accounts.main;

  @override
  void onInit() {
    super.onInit();
    Accounts.mainChanges.addListener(_onAccountChanged);
  }

  void _onAccountChanged() => onReload();

  @override
  List<SearchItem>? getDataList(SearchItemReply response) {
    if (!response.cursor.hasNext) {
      isEnd = true;
    }
    return response.items;
  }

  @override
  Future<LoadingState<SearchItemReply>> customGetData() {
    return ReplyGrpc.searchItem(
      account: Accounts.main,
      page: page,
      itemType: searchType == ReplySearchType.video
          ? SearchItemType.VIDEO
          : SearchItemType.ARTICLE,
      oid: controller.oid,
      type: controller.type,
      keyword: controller.keyword,
    );
  }

  @override
  void onClose() {
    Accounts.mainChanges.removeListener(_onAccountChanged);
    super.onClose();
  }
}
