import 'package:flutter/widgets.dart';

class ShellScrollBars {
  ShellScrollBars({
    required bool hideInstantly,
    required this.hideTopBar,
    required this.hideBottomBar,
  }) : offset = !hideInstantly && (hideTopBar || hideBottomBar)
           ? ValueNotifier(0.0)
           : null,
       showTop = hideInstantly && hideTopBar ? ValueNotifier(true) : null,
       showBottom = hideInstantly && hideBottomBar ? ValueNotifier(true) : null;

  final bool hideTopBar;
  final bool hideBottomBar;
  final ValueNotifier<double>? offset;
  final ValueNotifier<bool>? showTop, showBottom;
  bool useBottomNavigation = false;

  bool get bottomVisible =>
      useBottomNavigation && (showBottom?.value ?? (offset?.value ?? 0) == 0);

  void reveal() {
    offset?.value = 0;
    showTop?.value = true;
    showBottom?.value = true;
  }

  void dispose() {
    offset?.dispose();
    showTop?.dispose();
    showBottom?.dispose();
  }
}
