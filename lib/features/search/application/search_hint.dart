import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/search/data/search_local_store.dart';
import 'package:pili_aurora_next/features/search/data/search_repository.dart';

class SearchHint {
  SearchHint() {
    _subscription = _store.watchDefaultWord().listen(_setEnabled);
    _setEnabled(_store.showsDefaultWord);
  }

  static const _store = SearchLocalStore();
  static const _period = Duration(minutes: 5);
  final _hint = ValueNotifier('');
  late final StreamSubscription<bool> _subscription;
  bool _enabled = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastRequest;

  ValueListenable<String> get text => _hint;
  bool get enabled => _enabled;

  void _setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      unawaited(_refresh());
    } else {
      _generation++;
      _hint.value = '';
    }
  }

  void refreshIfDue() {
    if (_disposed || !_enabled) return;
    final lastRequest = _lastRequest;
    if (lastRequest == null ||
        DateTime.now().difference(lastRequest) >= _period) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    _lastRequest = DateTime.now();
    try {
      final keyword = await const SearchRepository().defaultKeyword();
      if (!_disposed &&
          generation == _generation &&
          _store.showsDefaultWord &&
          keyword != null) {
        _hint.value = keyword;
      }
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    _hint.dispose();
  }
}
