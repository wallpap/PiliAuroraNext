import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';

class ImSettingsItem extends StatelessWidget {
  const ImSettingsItem({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onRedirect,
  });

  final WhisperSetting item;
  final Future<void> Function(WhisperSettingEdit) onEdit;
  final ValueChanged<WhisperSettingsDestination> onRedirect;

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(fontSize: 14);
    final colorScheme = ColorScheme.of(context);
    final outline = colorScheme.outline;
    final subtitleStyle = TextStyle(fontSize: 13, color: outline);

    if (item case WhisperSettingToggle(
      :final title,
      :final subtitle,
      :final enabled,
    )) {
      return ListTile(
        dense: true,
        onTap: () => onEdit(SetWhisperToggle(!enabled)),
        title: Text(
          title,
          style: titleStyle,
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: subtitleStyle)
            : null,
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: enabled,
            onChanged: (value) => onEdit(SetWhisperToggle(value)),
          ),
        ),
      );
    }

    if (item case WhisperSettingRedirect(
      :final title,
      :final subtitle,
      :final summary,
      :final destination,
    )) {
      return ListTile(
        dense: true,
        onTap: () {
          if (destination != null) onRedirect(destination);
        },
        title: Text(
          title,
          style: titleStyle,
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: subtitleStyle)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary != null) Text(summary, style: subtitleStyle),
            Icon(color: outline, Icons.keyboard_arrow_right),
          ],
        ),
      );
    }

    if (item case WhisperSettingChoices(:final options)) {
      late final divider = Divider(
        height: 1,
        indent: 16,
        color: outline.withValues(alpha: 0.1),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          max(0, options.length * 2 - 1),
          (index) {
            if (index.isOdd) {
              return divider;
            }
            final optionIndex = index ~/ 2;
            final option = options[optionIndex];
            return ListTile(
              dense: true,
              onTap: () {
                if (!option.selected) {
                  onEdit(SelectWhisperOption(optionIndex, option.label));
                }
              },
              title: Text(option.label, style: titleStyle),
              trailing: option.selected
                  ? Icon(size: 20, Icons.check, color: colorScheme.primary)
                  : null,
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
