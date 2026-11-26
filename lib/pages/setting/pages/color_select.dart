import 'package:pili_aurora_next/common/widgets/animated_height.dart';
import 'package:pili_aurora_next/common/widgets/color_palette.dart';
import 'package:pili_aurora_next/common/widgets/main_navigation_icon.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/app_shell/domain/nav_bar_config.dart';
import 'package:pili_aurora_next/services/settings/theme/theme_color_type.dart';
import 'package:pili_aurora_next/services/settings/theme/theme_type.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/pages/setting/widgets/popup_item.dart';
import 'package:pili_aurora_next/pages/setting/widgets/select_dialog.dart';
import 'package:pili_aurora_next/pages/setting/widgets/setting_save.dart';
import 'package:pili_aurora_next/pages/setting/widgets/theme_color_dialog.dart';
import 'package:pili_aurora_next/services/settings/theme_preferences.dart';
import 'package:pili_aurora_next/router/get_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:collection/collection.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ColorSelectPage extends StatefulWidget {
  const ColorSelectPage({super.key});

  @override
  State<ColorSelectPage> createState() => _ColorSelectPageState();
}

class _ColorSelectPageState extends State<ColorSelectPage> {
  late var _variant = ThemePreferences.variant;
  late var _themeType = ThemePreferences.type;
  late var _currentColor = ThemePreferences.color;
  late var _dynamicColor = ThemePreferences.dynamicColor;
  bool _changingDynamicColor = false;
  bool _savingColor = false;

  bool _canPresent() => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  Future<bool> _save(
    String key,
    Future<void> Function() write,
    VoidCallback update, {
    VoidCallback? applyTheme,
    bool Function()? canPresent,
  }) => saveSetting(
    key: key,
    write: write,
    apply: () {
      if (mounted) setState(update);
      (applyTheme ?? Get.updateMyAppTheme)();
    },
    canPresent: canPresent ?? _canPresent,
  );

  Future<bool> _selectColor(int value, {bool Function()? canPresent}) async {
    if (_dynamicColor || _changingDynamicColor || _savingColor) return false;
    _savingColor = true;
    try {
      return await _save(
        SettingBoxKey.customColor,
        () => ThemePreferences.saveColor(value),
        () => _currentColor = value,
        canPresent: canPresent,
      );
    } finally {
      _savingColor = false;
    }
  }

  void _openCustomColor() {
    if (_dynamicColor || _changingDynamicColor || _savingColor) return;
    final seed = ThemePreferences.customSeed;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ThemeColorDialog(
        color: seed,
        variant: _variant,
        onApply: (color, canPresent) =>
            _selectColor(color.toARGB32(), canPresent: canPresent),
      ),
    );
  }

  Future<void> _onChanged([bool? val]) async {
    if (_changingDynamicColor || _savingColor) return;
    final enabled = val ?? !_dynamicColor;
    _changingDynamicColor = true;
    try {
      if (enabled && !await ThemeUtils.initPlatformState()) {
        if (_canPresent()) SmartDialog.showToast('暂时无法获取系统颜色，请稍后重试');
        return;
      }
      if (!mounted) return;
      await _save(
        SettingBoxKey.dynamicColor,
        () => ThemePreferences.saveDynamicColor(enabled),
        () => _dynamicColor = enabled,
      );
    } finally {
      _changingDynamicColor = false;
    }
  }

  late ThemeData theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    theme = Theme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = theme.textTheme.titleMedium!;
    final subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.viewPaddingOf(
      context,
    ).copyWith(top: 0, bottom: 0);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('选择应用主题')),
      body: ListView(
        padding: .only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
        ),
        children: [
          ListTile(
            onTap: () async {
              final result = await showDialog<ThemeType>(
                context: context,
                builder: (context) => SelectDialog<ThemeType>(
                  title: '主题模式',
                  value: _themeType,
                  values: ThemeType.values.map((e) => (e, e.label)).toList(),
                ),
              );
              if (mounted && result != null && result != _themeType) {
                await _save(
                  SettingBoxKey.themeMode,
                  () => ThemePreferences.saveType(result),
                  () => _themeType = result,
                  applyTheme: () => Get.changeThemeMode(
                    ThemeUtils.themeMode = result.toThemeMode,
                  ),
                );
              }
            },
            leading: const Icon(Icons.flashlight_on_outlined),
            title: Text('主题模式', style: titleStyle),
            subtitle: Text(
              '当前模式：${_themeType.label}',
              style: subTitleStyle,
            ),
          ),
          PopupListTile<FlexSchemeVariant>(
            enabled: !_dynamicColor,
            leading: const Icon(Icons.palette_outlined),
            title: '调色板风格',
            value: () => (_variant, _variant.variantName),
            options: FlexSchemeVariant.values
                .map((e) => (e, e.variantName))
                .toList(),
            onSelected: (value, _) async {
              await _save(
                SettingBoxKey.schemeVariant,
                () => ThemePreferences.saveVariant(value),
                () => _variant = value,
              );
            },
          ),
          ListTile(
            title: const Text('动态取色'),
            subtitle: _dynamicColor ? const Text('关闭动态取色后可自定义主题色') : null,
            leading: ExcludeFocus(
              child: Checkbox(
                value: _dynamicColor,
                onChanged: _onChanged,
                materialTapTargetSize: .shrinkWrap,
                visualDensity: const .new(horizontal: -4, vertical: -4),
              ),
            ),
            onTap: _onChanged,
          ),
          Padding(
            padding: padding + const .all(12),
            child: _buildColorPanel(),
          ),
          Padding(
            padding: padding,
            child: ExcludeFocus(
              child: IgnorePointer(
                child: Container(
                  height: size.height / 2,
                  width: size.width,
                  color: theme.colorScheme.surface,
                  child: const HomePage(),
                ),
              ),
            ),
          ),
          ExcludeFocus(
            child: IgnorePointer(
              child: NavigationBar(
                destinations: NavigationBarType.values
                    .map(
                      (item) => NavigationDestination(
                        icon: mainNavigationIcon(item),
                        label: item.label,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPanel() {
    final currentColor = _currentColor;
    final isCustom = !ThemePreferences.isPreset(currentColor);
    return AnimatedHeightWidgetExt(
      expand: !_dynamicColor,
      duration: const Duration(milliseconds: 200),
      child: Wrap(
        spacing: 22,
        runSpacing: 18,
        alignment: .center,
        children: [
          InkWell(
            onTap: _dynamicColor ? null : _openCustomColor,
            borderRadius: const .all(.circular(12)),
            child: Column(
              spacing: 3,
              children: [
                ColorPalette(
                  colorScheme: ThemePreferences.customSeed.asColorSchemeSeed(
                    _variant,
                    theme.brightness,
                  ),
                  selected: isCustom,
                ),
                Text(
                  '自定义',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCustom ? null : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...colorThemeTypes.mapIndexed(
            (i, e) {
              final color = e.color;
              final isCurr = currentColor == i;
              return GestureDetector(
                behavior: .opaque,
                onTap: _dynamicColor ? null : () => _selectColor(i),
                child: Column(
                  spacing: 3,
                  children: [
                    ColorPalette(
                      colorScheme: color.asColorSchemeSeed(
                        _variant,
                        theme.brightness,
                      ),
                      selected: isCurr,
                    ),
                    Text(
                      e.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurr ? null : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
