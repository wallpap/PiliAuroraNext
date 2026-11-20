import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:flutter/gestures.dart' show kTouchSlop;

final deviceTouchSlop = _readTouchSlop();

double _readTouchSlop() {
  final view = PlatformDispatcher.instance.views.firstOrNull;
  final physical = view?.gestureSettings.physicalTouchSlop;
  return physical == null ? kTouchSlop : physical / view!.devicePixelRatio;
}
