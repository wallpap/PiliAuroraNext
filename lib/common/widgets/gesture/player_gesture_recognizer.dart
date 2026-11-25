import 'package:flutter/gestures.dart'
    show
        GestureRecognizer,
        PointerCancelEvent,
        PointerEvent,
        RecognizerCallback,
        ScaleGestureRecognizer;

mixin PlayerGestureMixin on GestureRecognizer {
  bool isPosAllowed = true;

  @override
  T? invokeCallback<T>(
    String name,
    RecognizerCallback<T> callback, {
    String Function()? debugReport,
  }) {
    if (!isPosAllowed) return null;
    return super.invokeCallback(name, callback, debugReport: debugReport);
  }
}

class PlayerScaleGestureRecognizer extends ScaleGestureRecognizer
    with PlayerGestureMixin {
  PlayerScaleGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    super.dragStartBehavior,
    super.trackpadScrollCausesScale,
    super.trackpadScrollToScaleFactor,
  });

  bool handlingCancel = false;

  @override
  void handleEvent(PointerEvent event) {
    handlingCancel = event is PointerCancelEvent;
    try {
      super.handleEvent(event);
    } finally {
      handlingCancel = false;
    }
  }
}
