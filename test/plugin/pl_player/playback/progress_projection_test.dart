import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/progress_projection.dart';

void main() {
  PlaybackSnapshot snapshot(int loadId, PlaybackPhase phase) =>
      PlaybackSnapshot(
        snapshotVersion: 0,
        phase: phase,
        stage: PlaybackStage.observing,
        loadId: loadId,
        intent: const PlaybackIntent(),
        actual: const PlaybackActual(),
        capabilities: const PlaybackCapabilities(),
        presentation: const PlaybackPresentation(),
      );

  test('进度只接收已确认加载，独立于计划起点和实际落点', () {
    final progress = PlaybackProgressProjection();
    for (final phase in PlaybackPhase.values) {
      expect(progress.acceptsPosition(snapshot(1, phase)), isFalse);
    }
    progress.confirmLoad(1);
    for (final phase in PlaybackPhase.values) {
      expect(
        progress.acceptsPosition(snapshot(1, phase)),
        phase == PlaybackPhase.ready || phase == PlaybackPhase.ended,
      );
    }
    expect(progress.acceptsPosition(snapshot(2, PlaybackPhase.ready)), isFalse);
  });

  test('切换归属时撤销进度，旧加载不能污染新加载', () {
    final progress = PlaybackProgressProjection()
      ..confirmLoad(1)
      ..suspendPosition();
    expect(progress.acceptsPosition(snapshot(1, PlaybackPhase.ready)), isFalse);
    progress.confirmLoad(2);
    expect(progress.acceptsPosition(snapshot(1, PlaybackPhase.ended)), isFalse);
    expect(progress.acceptsPosition(snapshot(2, PlaybackPhase.ready)), isTrue);
  });
}
