import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets('拖动结束后重新采用播放位置，取消=$cancel', (tester) async {
      final progress = ValueNotifier(95);
      final seeks = <int>[];
      var cancellations = 0;
      await tester.pumpWidget(
        _app(progress, seeks.add, onDragCancel: () => cancellations++),
      );
      final track = find.byType(ProgressBar);
      final render = tester.renderObject<RenderProgressBar>(track);
      final gesture = await tester.startGesture(tester.getCenter(track));
      await gesture.moveBy(const Offset(30, 0));
      progress.value = 3;
      await tester.pump();

      final preview = SemanticsConfiguration();
      render.describeSemanticsConfiguration(preview);
      expect(preview.value, isNot('3%'));
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();

      final settled = SemanticsConfiguration();
      render.describeSemanticsConfiguration(settled);
      expect(settled.value, '3%');
      expect(seeks, hasLength(cancel ? 0 : 1));
      expect(cancellations, cancel ? 1 : 0);
    });
  }

  testWidgets('无障碍跳转使用毫秒，渲染位置等待外部确认', (tester) async {
    final progress = ValueNotifier(50);
    final seeks = <int>[];
    await tester.pumpWidget(_app(progress, seeks.add));
    final render = tester.renderObject<RenderProgressBar>(
      find.byType(ProgressBar),
    );
    render
      ..increaseAction()
      ..decreaseAction();
    expect(seeks, [55000, 45000]);

    final config = SemanticsConfiguration();
    render.describeSemanticsConfiguration(config);
    expect(config.value, '50%');
  });
}

Widget _app(
  ValueNotifier<int> progress,
  ValueChanged<int> onSeek, {
  VoidCallback? onDragCancel,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 300,
        child: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, position, child) => ProgressBar(
            progress: position,
            total: 100,
            onDragStart: (_) {},
            onDragCancel: onDragCancel,
            onSeek: onSeek,
            baseBarColor: Colors.black,
            progressBarColor: Colors.blue,
            bufferedBarColor: Colors.grey,
            thumbColor: Colors.blue,
            thumbGlowColor: Colors.blue,
          ),
        ),
      ),
    ),
  ),
);
