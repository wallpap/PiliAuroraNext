import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/utils/storage.dart';

enum SettingsValues {
  general,
  video;

  Box<dynamic> get _store => switch (this) {
    general => GStorage.setting,
    video => GStorage.video,
  };

  T? read<T>(String key) => switch (_store.get(key)) {
    final T value => value,
    _ => null,
  };

  T readOr<T>(String key, T fallback) => read<T>(key) ?? fallback;

  Future<void> save(String key, Object? value) => _store.put(key, value);

  Future<void> saveAll(Map<String, Object?> values) => _store.putAll(values);

  Future<void> reset(String key) => _store.delete(key);
}
