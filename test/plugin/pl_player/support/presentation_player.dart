import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pili_aurora_next/pages/danmaku/danmaku_model.dart';
import 'package:pili_aurora_next/pages/danmaku/interaction.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/double_tap_type.dart';

/// 只记录展示层的用户命令，未声明的依赖会使测试直接失败。
class PresentationPlayer implements PlPlayerController {
  @override
  bool enableTapDm = false;
  @override
  final enableShowDanmakuAdaptive = true.obs;
  @override
  final controlsLock = false.obs;
  @override
  final isFullScreen = false.obs;
  @override
  final showControls = false.obs;
  @override
  final volume = 0.8.obs;
  @override
  double maxVolume = 1;
  @override
  bool isLive = false;
  @override
  bool enableShrinkVideoSize = false;
  @override
  bool enableSlideVolumeBrightness = true;
  @override
  bool isFileSource = true;
  @override
  bool showSeekPreview = false;
  @override
  final position = 100.obs;
  @override
  final seekPosition = 100.obs;
  @override
  final duration = 600.obs;
  @override
  int durationInMilliseconds = 600000;
  @override
  num sliderScale = 600000;
  @override
  Duration? seekToPos;
  @override
  DanmakuInteractionHandle<DanmakuExtra>? danmakuInteraction;

  @override
  Player? get videoPlayerController => null;

  final ruleListeners = <VoidCallback>{};
  final fullScreenCommands = <(bool, bool)>[];
  final seeks = <Duration>[];
  final longPressCommands = <bool>[];
  final doubleTaps = <DoubleTapType>[];
  int playbackToggles = 0;
  int seekStarts = 0;
  int seekEnds = 0;

  @override
  set controls(bool value) => showControls.value = value;
  @override
  Future<void> onDoubleTapCenter() async => playbackToggles++;
  @override
  void doubleTapFuc(DoubleTapType type) => doubleTaps.add(type);
  @override
  Future<void> setLongPressStatus(bool value) async =>
      longPressCommands.add(value);
  @override
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) async => fullScreenCommands.add((status, inAppFullScreen));
  @override
  Future<void> setVolume(double value, {bool showIndicator = true}) async =>
      volume.value = value;
  @override
  void addDanmakuRuleListener(VoidCallback listener) =>
      ruleListeners.add(listener);
  @override
  void removeDanmakuRuleListener(VoidCallback listener) =>
      ruleListeners.remove(listener);
  @override
  void onSeekStart(int value) {
    seekPosition.value = value;
    seekStarts++;
  }

  @override
  void onSeekEnd() => seekEnds++;
  @override
  Future<void> seekTo(Duration value, {bool isSeek = true}) async =>
      seeks.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected player dependency: ${invocation.memberName}',
  );
}

class PresentationDanmaku implements DanmakuInteractionHandle<DanmakuExtra> {
  @override
  bool isValid = true;
  Object? selected;
  final entries = <DanmakuDisplaySnapshot<DanmakuExtra>>[];
  @override
  List<DanmakuDisplaySnapshot<DanmakuExtra>> get snapshot => [
    for (final entry in entries)
      DanmakuDisplaySnapshot(
        identity: entry.identity,
        text: entry.text,
        extra: entry.extra,
        bounds: entry.bounds,
        selectable: entry.selectable,
        selected: entry.identity == selected,
      ),
  ];
  @override
  DanmakuDisplaySnapshot<DanmakuExtra>? hitTest(Offset point) {
    if (!isValid) return null;
    for (final entry in snapshot) {
      if (entry.bounds.contains(point)) return entry;
    }
    return null;
  }

  @override
  bool select(Object identity) {
    selected = identity;
    return true;
  }

  @override
  bool clearSelection() {
    selected = null;
    return true;
  }
}
