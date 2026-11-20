import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;

void addObserverMobile(WidgetsBindingObserver observer) {
  if (PlatformUtils.isMobile) {
    WidgetsBinding.instance.addObserver(observer);
  }
}

void removeObserverMobile(WidgetsBindingObserver observer) {
  if (PlatformUtils.isMobile) {
    WidgetsBinding.instance.removeObserver(observer);
  }
}
