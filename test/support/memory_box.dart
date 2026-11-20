import 'dart:async';

import 'package:hive_ce/hive.dart';

/// 页面与状态测试共用的内存存储；未实现的操作直接报错。
class MemoryBox<T> implements Box<T> {
  MemoryBox([Map<dynamic, T>? initial]) : data = Map.of(initial ?? {});

  final Map<dynamic, T> data;
  StreamController<BoxEvent>? _events;

  @override
  Stream<BoxEvent> watch({dynamic key}) =>
      (_events ??= StreamController<BoxEvent>.broadcast()).stream.where(
        (event) => key == null || event.key == key,
      );

  @override
  T? get(dynamic key, {T? defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, T value) async {
    data[key] = value;
    _events?.add(BoxEvent(key, value, false));
  }

  @override
  Future<void> putAll(Map<dynamic, T> entries) async {
    data.addAll(entries);
    for (final entry in entries.entries) {
      _events?.add(BoxEvent(entry.key, entry.value, false));
    }
  }

  @override
  Future<void> delete(dynamic key) async {
    if (!data.containsKey(key)) return;
    data.remove(key);
    _events?.add(BoxEvent(key, null, true));
  }

  @override
  Future<int> clear() async {
    final count = data.length;
    for (final key in data.keys) {
      _events?.add(BoxEvent(key, null, true));
    }
    data.clear();
    return count;
  }

  @override
  Iterable<T> get values => data.values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
