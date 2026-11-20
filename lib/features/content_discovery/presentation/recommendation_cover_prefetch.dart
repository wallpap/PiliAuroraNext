import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class RecommendationCoverPrefetch {
  RecommendationCoverPrefetch(this._load);

  final Future<void> Function(String url) _load;
  List<String> _targets = const [];
  final _attempted = <String>{};
  bool _running = false;
  Timer? _settle;

  void update(Iterable<String> urls) {
    final targets = urls.toSet().toList();
    if (listEquals(targets, _targets)) return;
    _targets = targets;
    _attempted.retainAll(targets);
    _settle?.cancel();
    if (targets.isEmpty) {
      _settle = null;
      return;
    }
    _settle = Timer(const Duration(milliseconds: 120), () {
      _settle = null;
      _schedule();
    });
  }

  void _schedule() {
    if (_running || _settle != null || _targets.every(_attempted.contains)) {
      return;
    }
    _running = true;
    unawaited(
      SchedulerBinding.instance.scheduleTask(() async {
        try {
          if (_settle != null) return;
          final target = _targets
              .where((url) => !_attempted.contains(url))
              .firstOrNull;
          if (target == null) return;
          _attempted.add(target);
          await _load(target);
        } catch (_) {
          // 预取未命中由可见图片的正常加载处理。
        } finally {
          _running = false;
          _schedule();
        }
      }, Priority.idle),
    );
  }

  void clear() => update(const []);
}
