import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';

class PlayerSpeedIndicator extends StatelessWidget {
  const PlayerSpeedIndicator({
    super.key,
    required this.plPlayerController,
    required this.isFullScreen,
  });

  final PlPlayerController plPlayerController;
  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionalTranslation(
          translation: isFullScreen
              ? const Offset(0.0, 1.2)
              : const Offset(0.0, 0.8),
          child: Obx(
            () => AnimatedOpacity(
              curve: Curves.easeInOut,
              opacity: plPlayerController.longPressStatus.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0x88000000),
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: Obx(
                  () => Text(
                    '${plPlayerController.enableAutoLongPressSpeed ? (plPlayerController.longPressStatus.value ? plPlayerController.lastPlaybackSpeed : plPlayerController.playbackSpeed) * 2 : plPlayerController.longPressSpeed}倍速中',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerSeekIndicator extends StatelessWidget {
  const PlayerSeekIndicator({
    super.key,
    required this.plPlayerController,
    required this.isFullScreen,
  });

  final PlPlayerController plPlayerController;
  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 12);
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionalTranslation(
          translation: isFullScreen
              ? const Offset(0.0, 1.2)
              : const Offset(0.0, 0.8),
          child: Obx(
            () => AnimatedOpacity(
              curve: Curves.easeInOut,
              opacity: plPlayerController.isSeeking.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x88000000),
                  borderRadius: BorderRadius.all(Radius.circular(64)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  spacing: 2,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Obx(
                      () => Text(
                        DurationUtils.formatDuration(
                          plPlayerController.seekPosition.value,
                        ),
                        style: textStyle,
                      ),
                    ),
                    const Text('/', style: textStyle),
                    Obx(
                      () => Text(
                        DurationUtils.formatDuration(
                          plPlayerController.duration.value,
                        ),
                        style: textStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerVolumeIndicator extends StatelessWidget {
  const PlayerVolumeIndicator({super.key, required this.plPlayerController});

  final PlPlayerController plPlayerController;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.center,
        child: Obx(
          () {
            final volume = plPlayerController.volume.value;
            return AnimatedOpacity(
              curve: Curves.easeInOut,
              opacity: plPlayerController.volumeIndicator.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: const BoxDecoration(
                  color: Color(0x88000000),
                  borderRadius: BorderRadius.all(Radius.circular(64)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      volume == 0.0
                          ? Icons.volume_off
                          : volume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                      color: Colors.white,
                      size: 20.0,
                    ),
                    const SizedBox(width: 2.0),
                    Text(
                      '${(volume * 100.0).round()}%',
                      style: const TextStyle(
                        fontSize: 13.0,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
