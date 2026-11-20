import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:pili_aurora_next/core/async/rate_limiter.dart';

mixin ScrollOrRefreshMixin {
  ScrollController get scrollController;

  void animateToTop() => scrollController.animToTop();

  Future<void> onRefresh();

  void toTopOrRefresh() {
    if (scrollController.hasClients) {
      if (scrollController.position.pixels == 0) {
        ActionThrottle.run(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          onRefresh,
        );
      } else {
        animateToTop();
      }
    }
  }
}
