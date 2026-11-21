import 'dart:async';

abstract final class ActionThrottle {
  static final _timers = <String, Timer>{};

  static bool run(String tag, Duration interval, void Function() action) {
    if (_timers.containsKey(tag)) return true;
    _timers[tag] = Timer(interval, () => _timers.remove(tag));
    action();
    return false;
  }

  static void cancel(String tag) => _timers.remove(tag)?.cancel();
}

class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
