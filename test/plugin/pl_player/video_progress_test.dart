import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_progress.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';
import 'support/presentation_player.dart';

void main() {
  setUpAll(() => GStorage.setting = MemoryBox<dynamic>());

  testWidgets('精简进度条沿用显示偏好与 seek 临时展示，不接受拖动', (tester) async {
    final player = _ProgressPlayer();
    final page = _ProgressPage();
    Widget app({bool fullscreen = false}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 300,
          child: Stack(
            children: [
              CompactVideoProgress(
                plPlayerController: player,
                videoDetailController: page,
                isFullScreen: fullscreen,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.byType(ProgressBar), findsOneWidget);
    player.showControls.value = true;
    await tester.pump();
    expect(find.byType(ProgressBar), findsNothing);
    player.showControls.value = false;
    player.progressType = BtmProgressBehavior.alwaysHide;
    await tester.pump();
    expect(find.byType(ProgressBar), findsNothing);
    player.isSeeking.value = true;
    await tester.pump();
    expect(find.byType(ProgressBar), findsOneWidget);
    player.isSeeking.value = false;
    player.progressType = BtmProgressBehavior.onlyShowFullScreen;
    await tester.pumpWidget(app());
    expect(find.byType(ProgressBar), findsNothing);
    await tester.pumpWidget(app(fullscreen: true));
    expect(find.byType(ProgressBar), findsOneWidget);
    await tester.drag(
      find.byType(ProgressBar),
      const Offset(50, 0),
      warnIfMissed: false,
    );
    expect(player.seeks, isEmpty);
    expect(player.seekStarts, 0);
    player.progressType = BtmProgressBehavior.onlyHideFullScreen;
    await tester.pumpWidget(app(fullscreen: true));
    expect(find.byType(ProgressBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制条进度接受拖动，在松开时提交 seek，所有附加轨道关闭仍能更新', (tester) async {
    final player = _ProgressPlayer();
    final page = _ProgressPage()..showDmTrendChart.value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: VideoProgressTrack(
                controller: player,
                videoDetailController: page,
                color: Colors.blue,
                interactive: true,
              ),
            ),
          ),
        ),
      ),
    );
    final point = tester.getCenter(find.byType(ProgressBar));
    final gesture = await tester.startGesture(point);
    await gesture.moveBy(const Offset(50, 0));
    expect(player.seeks, isEmpty);
    await gesture.up();
    expect(player.seeks, hasLength(1));
    expect(player.seekStarts, 1);
    expect(player.seekEnds, 1);
    player.position.value = 200;
    await tester.pump();
    expect(tester.widget<ProgressBar>(find.byType(ProgressBar)).progress, 200);
    expect(tester.takeException(), isNull);
  });
}

class _ProgressPlayer extends PresentationPlayer {
  @override
  bool get enableBlock => false;
  @override
  bool get showViewPoints => false;
  @override
  bool get showDmChart => false;
  @override
  RxInt get buffered => _buffered;
  final _buffered = 120.obs;
  @override
  RxBool get isSeeking => _isSeeking;
  final _isSeeking = false.obs;
  @override
  int get progress => position.value;
  @override
  BtmProgressBehavior get progressType => _progressType;
  BtmProgressBehavior _progressType = BtmProgressBehavior.alwaysShow;
  set progressType(BtmProgressBehavior value) => _progressType = value;
}

class _ProgressPage implements VideoDetailController {
  @override
  final showDmTrendChart = false.obs;
  @override
  final dmTrend = Rx<LoadingState<List<double>>?>(null);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected page dependency: ${invocation.memberName}');
}
