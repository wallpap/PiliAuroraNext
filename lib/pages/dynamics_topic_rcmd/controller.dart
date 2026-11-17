import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';

class DynTopicRcmdController
    extends CommonListController<List<TopicItem>?, TopicItem> {
  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState<List<TopicItem>?>> customGetData() =>
      DynamicsHttp.dynTopicRcmd();
}
