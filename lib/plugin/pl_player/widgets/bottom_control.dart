import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_progress.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({
    super.key,
    required this.maxWidth,
    required this.isFullScreen,
    required this.controller,
    required this.buildBottomControl,
    required this.videoDetailController,
  });

  final double maxWidth;
  final bool isFullScreen;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;
  final VideoDetailController videoDetailController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    // 非全屏播放器已由页面约束到屏幕宽度，额外水平内边距会让底栏缩进。
    final horizontalPadding = isFullScreen ? 10.0 : 0.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              7,
            ),
            child: Obx(
              () => Offstage(
                offstage: !controller.showControls.value,
                child: VideoProgressTrack(
                  controller: controller,
                  videoDetailController: videoDetailController,
                  color: primary,
                  interactive: true,
                ),
              ),
            ),
          ),
          buildBottomControl(),
        ],
      ),
    );
  }
}
