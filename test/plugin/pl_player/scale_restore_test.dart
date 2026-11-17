import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/scale_restore.dart';

import 'support/presentation_player.dart';

void main() {
  testWidgets('还原动画回到单位矩阵，过程中退出释放 ticker 并取消交付', (tester) async {
    final player = PresentationPlayer()..showControls.value = true;
    final showRestore = true.obs;
    final transform = TransformationController(
      Matrix4.diagonal3Values(2, 2, 1),
    );
    addTearDown(transform.dispose);
    Widget app() => MaterialApp(
      home: Scaffold(
        body: PlayerScaleRestore(
          plPlayerController: player,
          transformationController: transform,
          showRestore: showRestore,
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.text('还原屏幕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(transform.value, Matrix4.identity());
    expect(showRestore.value, isFalse);
    transform.value = Matrix4.diagonal3Values(2, 2, 1);
    showRestore.value = true;
    await tester.pump();
    await tester.tap(find.text('还原屏幕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final intermediate = transform.value.clone();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(transform.value, intermediate);
    expect(tester.takeException(), isNull);
  });
}
