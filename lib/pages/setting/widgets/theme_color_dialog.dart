import 'package:flex_seed_scheme/flex_seed_scheme.dart' show FlexSchemeVariant;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/common/widgets/main_navigation_icon.dart';
import 'package:pili_aurora_next/features/app_shell/domain/nav_bar_config.dart';

class ThemeColorDialog extends StatefulWidget {
  const ThemeColorDialog({
    super.key,
    required this.color,
    required this.variant,
    required this.onApply,
  });

  final Color color;
  final FlexSchemeVariant variant;
  final Future<bool> Function(Color color, bool Function() canPresent) onApply;

  @override
  State<ThemeColorDialog> createState() => _ThemeColorDialogState();
}

class _ThemeColorDialogState extends State<ThemeColorDialog> {
  static final _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

  late HSVColor _draft = HSVColor.fromColor(widget.color.withAlpha(255));
  late final _hex = TextEditingController(text: _format(_draft.toColor()));
  Brightness? _previewBrightness;
  bool _valid = true;
  bool _saving = false;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _format(Color color) {
    final hex = (color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');
    return '#${hex.toUpperCase()}';
  }

  bool _canPresent() => mounted && ModalRoute.of(context)?.isCurrent == true;

  void _cancel() {
    if (!_saving) Navigator.of(context).pop();
  }

  Future<void> _apply() async {
    if (_saving || !_valid) return;
    setState(() => _saving = true);
    final saved = await widget.onApply(_draft.toColor(), _canPresent);
    if (!mounted) return;
    if (saved && _canPresent()) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  void _editHex(String text) {
    if (_saving) return;
    final digits = _hexPattern.firstMatch(text.trim())?.group(1);
    setState(() {
      _valid = digits != null;
      if (digits != null) {
        final color = Color(0xff000000 | int.parse(digits, radix: 16));
        final hsv = HSVColor.fromColor(color);
        _draft = hsv.saturation == 0 ? hsv.withHue(_draft.hue) : hsv;
      }
    });
  }

  void _pick(HSVColor color) {
    if (_saving) return;
    final text = _format(color.toColor());
    setState(() {
      _draft = color;
      _valid = true;
      _hex.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = _previewBrightness ?? theme.brightness;
    final color = _draft.toColor();
    final compact = MediaQuery.sizeOf(context).width < 440;
    return PopScope(
      canPop: !_saving,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: AlertDialog(
          title: const Text('自定义主题色'),
          scrollable: true,
          contentPadding: compact ? const .fromLTRB(16, 12, 16, 12) : null,
          content: SizedBox(
            width: 352,
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: compact ? 10 : 12,
              children: [
                _SaturationValuePalette(
                  color: _draft,
                  height: compact ? 120 : 144,
                  onChanged: _saving ? null : _pick,
                ),
                Row(
                  children: [
                    const Text('色相'),
                    Expanded(child: _buildHueSlider()),
                  ],
                ),
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hex,
                        enabled: !_saving,
                        textInputAction: .done,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '色值',
                          isDense: true,
                          errorText: _valid ? null : '请输入六位十六进制色值',
                        ),
                        onChanged: _editHex,
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: const .all(.circular(8)),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  alignment: .spaceBetween,
                  crossAxisAlignment: .center,
                  spacing: 12,
                  children: [
                    Text('预览', style: theme.textTheme.titleSmall),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final mode in const [
                          Brightness.light,
                          Brightness.dark,
                        ])
                          ChoiceChip(
                            label: Text(mode == .light ? '浅色' : '深色'),
                            selected: mode == brightness,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _previewBrightness = mode),
                          ),
                      ],
                    ),
                  ],
                ),
                _ThemePreview(
                  theme: ThemeUtils.buildSeedTheme(
                    color,
                    widget.variant,
                    brightness,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _saving || !_valid ? null : _apply,
              child: Text(_saving ? '正在应用…' : '应用'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHueSlider() => Stack(
    alignment: .center,
    children: [
      const Positioned(
        left: 14,
        right: 14,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: .all(.circular(4)),
            gradient: LinearGradient(
              colors: [
                Color(0xffff0000),
                Color(0xffffff00),
                Color(0xff00ff00),
                Color(0xff00ffff),
                Color(0xff0000ff),
                Color(0xffff00ff),
                Color(0xffff0000),
              ],
            ),
          ),
        ),
      ),
      Semantics(
        label: '色相',
        child: Slider(
          min: 0,
          max: 360,
          value: _draft.hue,
          padding: const .symmetric(horizontal: 14),
          activeColor: Colors.transparent,
          inactiveColor: Colors.transparent,
          thumbColor: Theme.of(context).colorScheme.primary,
          semanticFormatterCallback: (value) => '${value.round()}°',
          onChanged: _saving ? null : (value) => _pick(_draft.withHue(value)),
        ),
      ),
    ],
  );
}

class _SaturationValuePalette extends StatefulWidget {
  const _SaturationValuePalette({
    required this.color,
    required this.height,
    required this.onChanged,
  });

  final HSVColor color;
  final double height;
  final ValueChanged<HSVColor>? onChanged;

  @override
  State<_SaturationValuePalette> createState() =>
      _SaturationValuePaletteState();
}

class _SaturationValuePaletteState extends State<_SaturationValuePalette> {
  final _focus = FocusNode();
  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(double saturation, double value) => widget.onChanged?.call(
    widget.color
        .withSaturation((widget.color.saturation + saturation).clamp(0.0, 1.0))
        .withValue((widget.color.value + value).clamp(0.0, 1.0)),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-.05, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(.05, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(0, .05),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(0, -.05),
    },
    child: Focus(
      focusNode: _focus,
      canRequestFocus: widget.onChanged != null,
      onFocusChange: (_) => setState(() {}),
      child: Semantics(
        label: '饱和度与明度调色盘',
        value:
            '饱和度 ${(widget.color.saturation * 100).round()}%，'
            '明度 ${(widget.color.value * 100).round()}%',
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final hue = widget.color.withSaturation(1).withValue(1).toColor();
              final onChanged = widget.onChanged;

              void pick(Offset point) {
                onChanged?.call(
                  widget.color
                      .withSaturation((point.dx / width).clamp(0.0, 1.0))
                      .withValue((1 - point.dy / height).clamp(0.0, 1.0)),
                );
              }

              void start(DragStartDetails details) {
                _focus.requestFocus();
                pick(details.localPosition);
              }

              void update(DragUpdateDetails details) =>
                  pick(details.localPosition);

              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: GestureDetector(
                  onTapUp: onChanged == null
                      ? null
                      : (details) {
                          _focus.requestFocus();
                          pick(details.localPosition);
                        },
                  dragStartBehavior: .down,
                  onHorizontalDragStart: onChanged == null ? null : start,
                  onHorizontalDragUpdate: onChanged == null ? null : update,
                  onVerticalDragStart: onChanged == null ? null : start,
                  onVerticalDragUpdate: onChanged == null ? null : update,
                  child: Stack(
                    fit: .expand,
                    clipBehavior: .none,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: _radius,
                          gradient: LinearGradient(colors: [Colors.white, hue]),
                        ),
                      ),
                      DecoratedBox(
                        position: .foreground,
                        decoration: BoxDecoration(
                          borderRadius: _radius,
                          border: Border.all(
                            width: _focus.hasFocus ? 2 : 1,
                            color: _focus.hasFocus
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                          gradient: const LinearGradient(
                            begin: .topCenter,
                            end: .bottomCenter,
                            colors: [Color(0x00000000), Colors.black],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      Positioned(
                        left: width * widget.color.saturation - 9,
                        top: height * (1 - widget.color.value) - 9,
                        width: 18,
                        height: 18,
                        child: Container(
                          padding: const .all(1),
                          decoration: BoxDecoration(
                            shape: .circle,
                            border: Border.all(color: Colors.black),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: .circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Theme(
    data: theme,
    child: ExcludeFocus(
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Material(
            color: theme.scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: const .all(.circular(12)),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: .antiAlias,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .symmetric(horizontal: 12, vertical: 8),
                  child: Wrap(
                    crossAxisAlignment: .center,
                    spacing: 6,
                    children: [
                      Chip(
                        label: const Text('推荐'),
                        labelStyle: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        side: BorderSide.none,
                      ),
                      TextButton(onPressed: () {}, child: const Text('热门')),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放'),
                      ),
                    ],
                  ),
                ),
                NavigationBar(
                  height: 64,
                  destinations: [
                    for (final item in const [
                      NavigationBarType.home,
                      NavigationBarType.dynamics,
                      NavigationBarType.mine,
                    ])
                      NavigationDestination(
                        icon: mainNavigationIcon(item),
                        label: item.label,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
