import 'package:get/get.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

/// 内容页面只提供评论目标；查询和列表由评论模块维护。
abstract class CommonDynController extends GetxController {
  CommonDynController({this.count = -1});

  int count;
  int get oid;
  int get replyType;
  Object get sourceId;
  final commentSource = LoadingState<CommentTarget?>.loading().obs;

  void showComments() {
    commentSource.value = Success(oid > 0 ? (oid: oid, type: replyType) : null);
  }

  Future<void> onReload();

  late final RxBool showTitle = false.obs;
  late final horizontalPreview = Pref.horizontalPreview;
  late final List<double> ratio = Pref.dynamicDetailRatio;
  late final showDynActionBar = Pref.showDynActionBar;
}
