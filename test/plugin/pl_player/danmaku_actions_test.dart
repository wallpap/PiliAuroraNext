import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/pages/danmaku/danmaku_model.dart';
import 'package:pili_aurora_next/pages/danmaku/interaction.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/danmaku_actions.dart';

import 'support/presentation_player.dart';

void main() {
  late PresentationPlayer player;
  late PresentationDanmaku interaction;
  late PlayerDanmakuActions actions;

  setUp(() {
    interaction = PresentationDanmaku()
      ..entries.add(
        const DanmakuDisplaySnapshot(
          identity: 'live-message',
          text: '看看 01:23',
          extra: LiveDanmaku(id: 1, mid: 2, dmType: 0, ts: 0, ct: 0),
          bounds: Rect.fromLTWH(100, 30, 200, 30),
          selectable: true,
          selected: false,
        ),
      );
    player = PresentationPlayer()..danmakuInteraction = interaction;
    actions = PlayerDanmakuActions(
      plPlayerController: player,
      durationMs: () => null,
      liveRoomId: () => 3,
    );
  });
  tearDown(() => actions.dispose());

  testWidgets('弹幕点击消费本次抬起，直播时间文字不读取视频页或显示跳转', (tester) async {
    expect(actions.showAt(const Offset(150, 40)), isFalse);
    actions.selectAt(const Offset(150, 40));
    expect(actions.showAt(const Offset(150, 40)), isTrue);
    await tester.pumpWidget(_app(actions));
    expect(interaction.selected, 'live-message');
    expect(find.byIcon(Icons.gps_fixed_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    actions.clear();
    await tester.pump();
    expect(interaction.selected, isNull);
    expect(actions.showAt(const Offset(150, 40)), isFalse);
  });

  testWidgets('规则变化撤销选择，句柄失效后的重建可安全收起菜单', (tester) async {
    actions
      ..selectAt(const Offset(150, 40))
      ..showAt(const Offset(150, 40));
    await tester.pumpWidget(_app(actions));
    for (final listener in player.ruleListeners.toList()) {
      listener();
    }
    await tester.pump();
    expect(interaction.selected, isNull);
    actions
      ..selectAt(const Offset(150, 40))
      ..showAt(const Offset(150, 40));
    await tester.pump();
    interaction.isValid = false;
    await tester.pumpWidget(_app(actions));
    expect(interaction.selected, isNull);
    expect(tester.takeException(), isNull);
  });

  test('按下后选择失效的抬起仍被消费，随后空白点击可切控制条', () {
    actions.selectAt(const Offset(150, 40));
    interaction.selected = null;
    expect(actions.showAt(const Offset(150, 40)), isTrue);
    expect(actions.showAt(const Offset(150, 40)), isFalse);
  });
}

Widget _app(PlayerDanmakuActions actions) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => SizedBox(
        width: 600,
        height: 300,
        child: Stack(children: [actions.buildOverlay(context, 600)]),
      ),
    ),
  ),
);
