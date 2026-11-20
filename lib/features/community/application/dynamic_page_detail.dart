import 'dart:async';

import 'package:pili_aurora_next/features/community/application/content_page_detail.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';

class DynamicDetailController extends ContentPageDetail {
  DynamicDetailController(
    this._details, {
    super.count,
    super.onFeedback,
    this.onScrollReset,
  });

  final DynamicDetails _details;
  final void Function()? onScrollReset;

  @override
  int oid = 0;
  @override
  int replyType = 0;
  late DynamicItemModel dynItem;
  Account? _sourceAccount;
  int _sourceVersion = 0;
  bool _sourceReady = false;
  Timer? _replySubjectRefresh;
  Future<void> Function()? refreshComments;

  @override
  Object get sourceId => replyType == 1 ? IdUtils.av2bv(oid) : oid;

  @override
  void open() {
    Accounts.heartbeatChanges.addListener(_onAccountChanged);
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

  void _onAccountChanged() {
    if (_sourceReady || isClosed) return;
    commentSource.value = LoadingState.loading();
    unawaited(_loadCommentSource());
  }

  Future<void> _loadCommentSource() async {
    final account = Accounts.heartbeat;
    if (isClosed || identical(_sourceAccount, account)) return;
    _sourceAccount = account;
    final version = ++_sourceVersion;
    final item = dynItem;
    try {
      final result = await _details.load(account, item.idStr);
      if (isClosed ||
          version != _sourceVersion ||
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
      if (version == _sourceVersion) _sourceAccount = null;
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
      onFeedback?.call('设置成功');
    } else {
      onFeedback?.call(result.toString());
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
      onFeedback?.call(
        response?.trim().isNotEmpty == true ? response! : '设置成功',
      );
      _replySubjectRefresh?.cancel();
      _replySubjectRefresh = Timer(const Duration(milliseconds: 500), () {
        if (ownsTarget()) onReload();
      });
    } else if (result is Error) {
      onFeedback?.call(result.toString());
    }
  }

  @override
  void close() {
    Accounts.heartbeatChanges.removeListener(_onAccountChanged);
    _replySubjectRefresh?.cancel();
    super.close();
  }

  @override
  Future<void> onReload() {
    if (isClosed) return Future.value();
    onScrollReset?.call();
    return _sourceReady
        ? refreshComments?.call() ?? Future.value()
        : _loadCommentSource();
  }
}
