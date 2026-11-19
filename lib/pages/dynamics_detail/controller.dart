import 'dart:async';

import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadMixin;
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class DynamicDetailController extends CommonDynController with ReloadMixin {
  DynamicDetailController(this._details, {super.count});

  final DynamicDetails _details;

  @override
  int oid = 0;
  @override
  int replyType = 0;
  late DynamicItemModel dynItem;
  bool _loadingSource = false;
  bool _sourceReady = false;
  Timer? _replySubjectRefresh;
  Future<void> Function()? refreshComments;

  @override
  Object get sourceId => replyType == 1 ? IdUtils.av2bv(oid) : oid;

  @override
  void onInit() {
    super.onInit();
    final commentType = dynItem.basic?.commentType;
    final commentIdStr = dynItem.basic?.commentIdStr;
    if (commentType != null &&
        commentType != 0 &&
        commentIdStr != null &&
        commentIdStr.isNotEmpty) {
      _init(commentIdStr, commentType);
    } else {
      _loadCommentSource();
    }
  }

  Future<void> _loadCommentSource() async {
    if (isClosed || _loadingSource) return;
    _loadingSource = true;
    final item = dynItem;
    final account = Accounts.heartbeat;
    try {
      final result = await _details.load(account, item.idStr);
      if (isClosed ||
          !identical(item, dynItem) ||
          !identical(account, Accounts.heartbeat)) {
        return;
      }
      if (result case Success(:final response)) {
        _init(response.basic?.commentIdStr, response.basic?.commentType);
      } else if (result is Error) {
        commentSource.value = result;
      }
    } finally {
      _loadingSource = false;
    }
  }

  void _init(String? commentIdStr, int? commentType) {
    final id = int.tryParse(commentIdStr ?? '');
    if (id == null || id <= 0 || commentType == null || commentType <= 0) {
      commentSource.value = const Error('动态缺少有效的评论来源，请重试');
      return;
    }
    oid = id;
    replyType = commentType;
    _sourceReady = true;
    showComments();
  }

  Future<LoadingState<void>> onSetPubSetting(
    bool isPrivate,
    Object dynId,
  ) async {
    if (isClosed) return const Error('页面已关闭');
    final account = Accounts.main;
    final item = dynItem;
    if (dynId.toString() != item.idStr.toString()) {
      return const Error('动态已变更，请重试');
    }
    final result = await _details.setVisibility(account, dynId, isPrivate);
    if (isClosed ||
        !identical(account, Accounts.main) ||
        !identical(item, dynItem)) {
      return const Error('账号或动态已变更');
    }
    if (result == null) return const Error('正在设置可见范围，请稍候');
    if (result.isSuccess) {
      item.modules.moduleAuthor?.badgeText = isPrivate ? null : '仅自己可见';
      SmartDialog.showToast('设置成功');
    } else {
      result.toast();
    }
    return result;
  }

  Future<void> onSetReplySubject(int action) async {
    if (isClosed) return;
    final account = Accounts.main;
    final item = dynItem;
    final oid = this.oid;
    final type = replyType;
    bool ownsTarget() =>
        !isClosed &&
        identical(account, Accounts.main) &&
        identical(item, dynItem) &&
        oid == this.oid &&
        type == replyType;
    final result = await _details.setReplySubject(account, oid, type, action);
    if (!ownsTarget()) return;
    if (result case Success(:final response)) {
      SmartDialog.showToast(
        response?.trim().isNotEmpty == true ? response! : '设置成功',
      );
      _replySubjectRefresh?.cancel();
      _replySubjectRefresh = Timer(const Duration(milliseconds: 500), () {
        if (ownsTarget()) onReload();
      });
    } else if (result is Error) {
      result.toast();
    }
  }

  @override
  void onClose() {
    _replySubjectRefresh?.cancel();
    super.onClose();
  }

  @override
  Future<void> onReload() {
    reload = true;
    return _sourceReady
        ? refreshComments?.call() ?? Future.value()
        : _loadCommentSource();
  }
}
