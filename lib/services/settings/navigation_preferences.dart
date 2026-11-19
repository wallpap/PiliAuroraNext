import 'package:pili_aurora_next/models/common/nav_bar_config.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

abstract final class NavigationPreferences {
  static NavigationBarType? _tab(Object? value) => switch (value) {
    int index when index >= 0 && index < NavigationBarType.values.length =>
      NavigationBarType.values[index],
    _ => null,
  };

  static NavigationBarType get defaultTab =>
      _tab(GStorage.setting.get(SettingBoxKey.defaultHomePage)) ?? .home;

  static Future<void> saveDefaultTab(NavigationBarType value) =>
      GStorage.setting.put(SettingBoxKey.defaultHomePage, value.index);

  static List<int>? orderFor(String key) {
    final saved = GStorage.setting.get(key);
    return saved is List ? saved.whereType<int>().toSet().toList() : null;
  }

  static Future<void> saveOrder(String key, Iterable<int> order) =>
      GStorage.setting.put(key, order.toList());

  static Future<void> resetOrder(String key) => GStorage.setting.delete(key);

  static ({List<NavigationBarType> tabs, int index}) read() {
    final saved = orderFor(SettingBoxKey.navBarSort);
    final configured = <NavigationBarType>[
      for (final value in saved ?? const <int>[]) ?_tab(value),
    ];
    final tabs = configured.isEmpty
        ? NavigationBarType.values
        : List<NavigationBarType>.unmodifiable(configured);
    final index = tabs.indexOf(defaultTab);
    return (tabs: tabs, index: index < 0 ? 0 : index);
  }
}
