import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:pili_aurora_next/services/desktop_playback_request.dart';
import 'package:pili_aurora_next/services/desktop_playback_windows.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/player_loading.dart';

class DesktopPlaybackLaunch extends StatefulWidget {
  const DesktopPlaybackLaunch({super.key, required this.request});
  final DesktopPlaybackRequest request;

  @override
  State<DesktopPlaybackLaunch> createState() => _DesktopPlaybackLaunchState();
}

class _DesktopPlaybackLaunchState extends State<DesktopPlaybackLaunch> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final windows = DesktopPlaybackWindows.instance;
        unawaited(
          windows.showPlayerWindow().catchError(
            (Object _) => windows.failPlayerWindow(),
          ),
        );
        Get.offNamed(widget.request.route, arguments: widget.request.arguments);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const PlayerLoadingPanel();
}
