import 'dart:ui';

import 'package:flex_seed_scheme/flex_seed_scheme.dart' show FlexSchemeVariant;
import 'package:pili_aurora_next/services/settings/theme/theme_color_type.dart';
import 'package:pili_aurora_next/services/settings/theme/theme_type.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

abstract final class ThemePreferences {
  static ThemeType get type => _enum(
    SettingBoxKey.themeMode,
    ThemeType.values,
    ThemeType.system,
  );

  static FlexSchemeVariant get variant => _enum(
    SettingBoxKey.schemeVariant,
    FlexSchemeVariant.values,
    FlexSchemeVariant.material3Legacy,
  );

  static int get color =>
      switch (GStorage.setting.get(SettingBoxKey.customColor)) {
        final int value => value,
        _ => 0,
      };

  static bool get dynamicColor =>
      switch (GStorage.setting.get(SettingBoxKey.dynamicColor)) {
        final bool value => value,
        _ => true,
      };

  static bool isPreset(int value) =>
      value >= 0 && value < colorThemeTypes.length;

  static Color seedColor(int value) =>
      isPreset(value) ? colorThemeTypes[value].color : Color(value);

  static Future<void> saveType(ThemeType value) =>
      GStorage.setting.put(SettingBoxKey.themeMode, value.index);

  static Future<void> saveVariant(FlexSchemeVariant value) =>
      GStorage.setting.put(SettingBoxKey.schemeVariant, value.index);

  static Future<void> saveColor(int value) =>
      GStorage.setting.put(SettingBoxKey.customColor, value);

  static Future<void> saveDynamicColor(bool value) =>
      GStorage.setting.put(SettingBoxKey.dynamicColor, value);

  static T _enum<T>(String key, List<T> values, T fallback) => switch (GStorage
      .setting
      .get(key)) {
    final int index when index >= 0 && index < values.length => values[index],
    _ => fallback,
  };
}
