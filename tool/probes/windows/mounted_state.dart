import 'package:flutter/widgets.dart';

S? findMountedDescendant<S extends State>(State ancestor) =>
    ancestor.mounted ? findMountedState<S>(ancestor.context as Element) : null;

S? findMountedState<S extends State>([Element? root]) {
  S? result;
  void visit(Element element) {
    if (result != null) return;
    if (element case StatefulElement(state: final S state)) {
      result = state;
    } else {
      element.visitChildren(visit);
    }
  }

  final start = root ?? WidgetsBinding.instance.rootElement;
  if (start != null) visit(start);
  return result;
}
