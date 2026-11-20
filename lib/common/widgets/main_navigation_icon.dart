import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/features/app_shell/domain/nav_bar_config.dart';

Icon mainNavigationIcon(NavigationBarType type, {bool selected = false}) =>
    switch ((type, selected)) {
      (.home, false) => const Icon(Icons.home_outlined),
      (.home, true) => const Icon(Icons.home),
      (.dynamics, false) => const Icon(CustomIcons.motion_photos_on_outlined),
      (.dynamics, true) => const Icon(CustomIcons.motion_photos_on),
      (.mine, false) => const Icon(Icons.person_outline),
      (.mine, true) => const Icon(Icons.person),
    };
