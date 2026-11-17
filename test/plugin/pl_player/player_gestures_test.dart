import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_actions.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/player_gestures.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/double_tap_type.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';
import 'support/presentation_player.dart';

void main() {
  setUpAll(() => GStorage.setting = MemoryBox<dynamic>());

  testWidgets('触摸双击保持左中右分区，长按在松开或取消时恢复倍速', (tester) async {
    final player = PresentationPlayer();
    await tester.pumpWidget(_app(player));
    final rect = tester.getRect(find.byKey(_surface));
    for (final (fraction, expected) in [
      (0.1, DoubleTapType.left),
      (0.5, DoubleTapType.center),
      (0.9, DoubleTapType.right),
    ]) {
      final point = Offset(rect.left + rect.width * fraction, rect.center.dy);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 350));
      expect(player.doubleTaps.last, expected);
    }
    for (final cancel in [false, true]) {
      player.longPressCommands.clear();
      final gesture = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(player.longPressCommands, [true]);
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      expect(player.longPressCommands, [true, false]);
    }
  });

  testWidgets('右键和中键等抬起后才切全屏，取消不触发', (tester) async {
    final player = PresentationPlayer();
    await tester.pumpWidget(_app(player));
    final position = tester.getCenter(find.byKey(_surface));
    for (final buttons in [kSecondaryMouseButton, kMiddleMouseButton]) {
      final gesture = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      expect(player.fullScreenCommands, isEmpty);
      await gesture.up();
      expect(player.fullScreenCommands, [
        (true, buttons == kSecondaryMouseButton),
      ]);
      player.fullScreenCommands.clear();
      final cancelled = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await cancelled.cancel();
      expect(player.fullScreenCommands, isEmpty);
    }
    expect(player.playbackToggles, 0);
    await tester.pumpWidget(const SizedBox());
    expect(player.ruleListeners, isEmpty);
  }, skip: !Platform.isWindows);

  testWidgets('锁定全屏时右键退出先解除锁定和控制条', (tester) async {
    final player = PresentationPlayer()
      ..isFullScreen.value = true
      ..controlsLock.value = true
      ..showControls.value = true;
    await tester.pumpWidget(_app(player));
    await tester.tapAt(
      tester.getCenter(find.byKey(_surface)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    expect(player.fullScreenCommands, [(false, true)]);
    expect(player.controlsLock.value, isFalse);
    expect(player.showControls.value, isFalse);
  }, skip: !Platform.isWindows);

  testWidgets('桌面单击切播放，锁定后忽略单击，滚轮保留音量控制', (tester) async {
    final player = PresentationPlayer();
    await tester.pumpWidget(_app(player));
    final position = tester.getCenter(find.byKey(_surface));
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.playbackToggles, 1);
    player.controlsLock.value = true;
    await tester.pump();
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.playbackToggles, 1);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, -400),
      ),
    );
    expect(player.volume.value, closeTo(0.9, 0.001));
  }, skip: !Platform.isWindows);

  testWidgets('触控板水平进退在松开时提交，直播保持禁止 seek', (tester) async {
    final player = PresentationPlayer();
    await tester.pumpWidget(_app(player));
    final position = tester.getCenter(find.byKey(_surface));
    for (final live in [false, true]) {
      player.isLive = live;
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(position));
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(position, pan: const Offset(10, 0)),
      );
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(position, pan: const Offset(70, 0)),
      );
      expect(player.seeks, isEmpty);
      await tester.sendEventToBinding(pointer.panZoomEnd());
      if (!live) {
        expect(player.seeks, [const Duration(seconds: 160)]);
        expect(player.seekStarts, 1);
        expect(player.seekEnds, 1);
        expect(player.seekToPos, isNull);
        player.seeks.clear();
      } else {
        expect(player.seeks, isEmpty);
      }
    }
  });
}

const _surface = Key('video');

Widget _app(PresentationPlayer player) => MaterialApp(
  home: Scaffold(
    body: Center(child: _GestureHost(player: player)),
  ),
);

class _GestureHost extends StatefulWidget {
  const _GestureHost({required this.player});
  final PresentationPlayer player;
  @override
  State<_GestureHost> createState() => _GestureHostState();
}

class _GestureHostState extends State<_GestureHost> {
  late final actions = PlayerDanmakuActions(
    plPlayerController: widget.player,
    durationMs: () => 600000,
    liveRoomId: () => 1,
  );
  late final gestures = PlayerGestures(
    plPlayerController: widget.player,
    danmakuActions: actions,
    context: () => context,
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 600,
    height: 300,
    child: gestures.buildSurface(
      width: 600,
      height: 300,
      child: const ColoredBox(key: _surface, color: Colors.black),
    ),
  );
  @override
  void dispose() {
    gestures.dispose();
    actions.dispose();
    super.dispose();
  }
}
