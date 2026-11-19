import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/scroll_bars.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:material_ui/material_ui.dart';

abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  ShellScrollBars? get scrollBars;
  bool get respondsToScroll => true;
  bool get needsCorrection => false;

  Widget onBuild(Widget child) {
    final bars = scrollBars;
    if (bars?.offset != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: onNotificationType2,
        child: child,
      );
    }
    if (bars?.showTop != null || bars?.showBottom != null) {
      return NotificationListener<UserScrollNotification>(
        onNotification: onNotificationType1,
        child: child,
      );
    }
    return child;
  }

  bool onNotificationType1(UserScrollNotification notification) {
    final bars = scrollBars;
    if (bars == null || !bars.useBottomNavigation || !respondsToScroll) {
      return false;
    }
    if (notification.metrics.axis == .horizontal) return false;
    switch (notification.direction) {
      case .forward:
        bars.showTop?.value = true;
        bars.showBottom?.value = true;
      case .reverse:
        bars.showTop?.value = false;
        bars.showBottom?.value = false;
      case _:
    }
    return false;
  }

  bool onNotificationType2(ScrollNotification notification) {
    final bars = scrollBars;
    if (bars == null || !bars.useBottomNavigation || !respondsToScroll) {
      return false;
    }
    final offset = bars.offset;
    if (offset == null) return false;

    final metrics = notification.metrics;
    if (metrics.axis == .horizontal) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) return false;
      final pixel = metrics.pixels;
      final scrollDelta = notification.scrollDelta ?? 0;
      if (pixel < 0.0 && scrollDelta > 0) return false;
      if (needsCorrection) {
        final value = offset.value;
        final newValue = clampDouble(
          value + scrollDelta,
          0.0,
          Style.topBarHeight,
        );
        final correction = value - newValue;
        if (correction != 0) {
          offset.value = newValue;
          if (pixel < 0.0 && scrollDelta < 0.0 && value > 0.0) {
            return false;
          }
          Scrollable.of(notification.context!).position.correctBy(correction);
        }
      } else {
        offset.value = clampDouble(
          offset.value + scrollDelta,
          0,
          Style.topBarHeight,
        );
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      offset.value = clampDouble(
        offset.value + notification.overscroll,
        0,
        Style.topBarHeight,
      );
      return false;
    }

    return false;
  }
}
