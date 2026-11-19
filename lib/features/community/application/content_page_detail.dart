import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

class DetailValue<T> extends ValueNotifier<T> {
  DetailValue(super.value);

  void refresh() => notifyListeners();
}

abstract class ContentPageDetail {
  ContentPageDetail({this.count = -1, this.onFeedback});

  int count;
  final void Function(String)? onFeedback;
  int get oid;
  int get replyType;
  Object get sourceId;
  final commentSource = DetailValue(LoadingState<CommentTarget?>.loading());
  bool _closed = false;
  bool get isClosed => _closed;

  void open();

  @mustCallSuper
  void close() {
    if (_closed) return;
    _closed = true;
    commentSource.dispose();
    showTitle.dispose();
  }

  void showComments() {
    commentSource.value = Success(oid > 0 ? (oid: oid, type: replyType) : null);
  }

  Future<void> onReload();

  final showTitle = ValueNotifier(false);
  void setShowTitle(bool value) {
    if (!_closed) showTitle.value = value;
  }

  late final horizontalPreview = Pref.horizontalPreview;
  late final List<double> ratio = Pref.dynamicDetailRatio;
  late final showDynActionBar = Pref.showDynActionBar;
}
