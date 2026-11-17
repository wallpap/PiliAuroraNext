import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/common/scroll_or_refresh.dart';

/// 兼容首页壳；只暴露当前 Widget 的滚动和刷新意图。
class DiscoveryPageHandle with ScrollOrRefreshMixin {
  DiscoveryPageHandle(this._scroll, this._refresh);
  final ScrollController Function() _scroll;
  final Future<void> Function() _refresh;
  @override
  ScrollController get scrollController => _scroll();
  @override
  Future<void> onRefresh() => _refresh();
}
