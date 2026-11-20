import 'package:pili_aurora_next/common/widgets/custom_tooltip.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/core/text/string_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/settings/display_preferences.dart';
import 'package:material_ui/material_ui.dart';

bool enableEmoteTooltip = DisplayPreferences.showEmoteTooltips;

final TriggerMode_ kTriggerMode = PlatformUtils.isDesktop ? .mouse : .longPress;

Widget emoteTooltipBuilder({
  bool? enable,
  double size = 80.0,
  required TriggerMode_ triggerMode,
  required String? url,
  required String? emote,
  String? jumpUrl,
  required ColorScheme colorScheme,
  required Widget child,
}) {
  if (enable ?? enableEmoteTooltip) {
    return CustomTooltip(
      color: colorScheme.isDark
          ? colorScheme.surfaceContainerHigh
          : colorScheme.surface,
      shadow: Colors.black,
      triggerMode: triggerMode,
      jumpUrl: jumpUrl,
      overlayWidget: () {
        Widget overlay = NetworkImgLayer(
          src: url,
          type: .emote,
          width: size,
          height: size,
          fit: .contain,
        );
        if (emote != null) {
          overlay = Column(
            spacing: 8,
            mainAxisSize: .min,
            children: [
              overlay,
              Text.rich(
                TextSpan(
                  text: emote.emote,
                  children: jumpUrl != null && jumpUrl.isNotEmpty
                      ? [
                          WidgetSpan(
                            child: Icon(
                              Icons.keyboard_arrow_right,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                          ),
                        ]
                      : null,
                ),
                style: const TextStyle(fontSize: 12, height: 1),
              ),
            ],
          );
        }
        return Padding(padding: const .all(8.0), child: overlay);
      },
      child: child,
    );
  }
  return child;
}
