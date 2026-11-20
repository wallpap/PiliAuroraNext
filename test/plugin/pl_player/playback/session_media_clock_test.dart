import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:pili_aurora_next/pages/danmaku/window_renderer.dart';
import 'package:pili_aurora_next/pages/danmaku/window_screen.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/media_clock.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final buffering in [false, true]) {
    testWidgets('播放状态切换${buffering ? '缓冲' : '暂停'}立即冻结媒体锚点', (tester) async {
      var now = 2000000;
      final runtime = SamplingSessionRuntime();
      final session = PlaybackSession(
        runtime: runtime,
        mediaClockNowUs: () => now,
      );
      final owner = session.attach();
      addTearDown(owner.close);
      await tester.runAsync(
        () => owner.load(sessionPlan('clock'), start: PlaybackStartPolicy.play),
      );
      runtime.emitActual(
        session.loadId,
        const PlaybackActual(playing: true, buffering: false),
      );
      const anchor = PlaybackMediaAnchor(
        positionUs: 1000000,
        observedAtUs: 2000000,
        effectiveRate: 1,
        advancing: true,
        ready: true,
        continuity: 1,
        validForUs: 500000,
      );
      void emitAnchor(PlaybackMediaAnchor value) => runtime.eventController.add(
        PlaybackRuntimeMediaAnchor(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
          seekSequence: 0,
          anchor: value,
        ),
      );
      emitAnchor(anchor);
      expect(session.currentMediaAnchor!.advancing, isTrue);
      final renderer = DanmakuWindowRenderer<void>(
        option: const DanmakuOption(fontSize: 20, duration: 8, safeArea: false),
        size: const Size(320, 120),
      );
      addTearDown(renderer.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 120,
              child: DanmakuWindowScreen<void>(
                renderer: renderer,
                clock: session,
                size: const Size(320, 120),
                monotonicUs: () => now,
                frameTimeUs: () => now,
                prepareFrame: (r, p, {required effectiveRate}) {
                  if (r.validUntilUs != r.validFromUs) return;
                  r.prepare(
                    [
                      DanmakuWindowContent(
                        'scroll',
                        r.validFromUs,
                        DanmakuContentItem<void>('state'),
                      ),
                    ],
                    generation: r.generation,
                    preparedUntilUs: r.validFromUs + 10000000,
                  );
                },
              ),
            ),
          ),
        ),
      );
      now += 25000;
      await tester.pump(const Duration(microseconds: 25000));
      final stoppedAt = renderer.presentationTimeUs;
      runtime.emitActual(
        session.loadId,
        PlaybackActual(playing: buffering, buffering: buffering),
      );
      expect(session.currentMediaAnchor!.advancing, isFalse);
      final frozen = session.currentMediaAnchor!;
      expect(frozen.positionUs, 1025000);
      expect(frozen.observedAtUs, now);
      expect(frozen.positionAt(9000000), frozen.positionUs);
      expect(renderer.presentationTimeUs, stoppedAt);
      await tester.pump();
      expect(renderer.presentationTimeUs, stoppedAt);
      expect(tester.hasRunningAnimations, isFalse);
      // 状态切换前的 worker 结果迟到时，暂停不能被旧采样撤销。
      emitAnchor(anchor);
      emitAnchor(
        const PlaybackMediaAnchor(
          positionUs: 1040000,
          observedAtUs: 2040000,
          effectiveRate: 1,
          advancing: true,
          ready: true,
          continuity: 1,
          validForUs: 500000,
        ),
      );
      expect(session.currentMediaAnchor!.advancing, isFalse);
      expect(session.currentMediaAnchor!.positionUs, frozen.positionUs);
      var samples = 0;
      runtime.onSample = () => samples++;
      now += 1000000;
      await tester.pump(const Duration(seconds: 1));
      expect(renderer.presentationTimeUs, stoppedAt);
      runtime.emitActual(
        session.loadId,
        const PlaybackActual(playing: true, buffering: false),
      );
      expect(samples, 1);
      expect(session.currentMediaAnchor!.advancing, isFalse);
      expect(session.currentMediaAnchor!.positionUs, frozen.positionUs);
      expect(tester.hasRunningAnimations, isFalse);
      // 暂停期间的读取结果在恢复后返回，也不能包含暂停时长的外推。
      emitAnchor(anchor);
      expect(session.currentMediaAnchor!.advancing, isFalse);
      final resumed = PlaybackMediaAnchor(
        positionUs: frozen.positionUs,
        observedAtUs: now,
        effectiveRate: 1,
        advancing: true,
        ready: true,
        continuity: 1,
        validForUs: 500000,
      );
      emitAnchor(resumed);
      expect(session.currentMediaAnchor, same(resumed));
      expect(session.currentMediaAnchor!.positionAt(now + 20000), 1045000);
      now += 20000;
      await tester.pump(const Duration(milliseconds: 20));
      expect(renderer.presentationTimeUs, 1045000);
      await tester.pumpWidget(const SizedBox.shrink());
      owner.close();
      await tester.pump();
      expect(session.isDisposed, isTrue);
    });
  }

  test('暂停加载进入 ready 后主动取得首个媒体锚点', () async {
    final runtime = SamplingSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    const anchor = PlaybackMediaAnchor(
      positionUs: 0,
      observedAtUs: 1000000,
      effectiveRate: 1,
      advancing: false,
      ready: true,
      continuity: 1,
      validForUs: 500000,
    );
    runtime.onSample = () => runtime.eventController.add(
      PlaybackRuntimeMediaAnchor(
        runtimeId: runtime.runtimeId,
        loadId: session.loadId,
        seekSequence: 0,
        anchor: anchor,
      ),
    );
    await owner.load(sessionPlan('paused'), start: PlaybackStartPolicy.pause);
    expect(session.currentMediaAnchor, same(anchor));
    owner.close();
    await runtime.released;
  });

  test('媒体时钟独立发布，丢弃其他 runtime、旧加载和旧 seek 的采样', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('clock'), start: PlaybackStartPolicy.play);
    final samples = <PlaybackMediaAnchor?>[];
    final subscription = session.mediaAnchors.listen(samples.add);
    const anchor = PlaybackMediaAnchor(
      positionUs: 1000000,
      observedAtUs: 2000000,
      effectiveRate: 1,
      advancing: true,
      ready: true,
      continuity: 1,
      validForUs: 500000,
    );
    void emit({int? runtimeId, int? loadId, int sequence = 0}) {
      runtime.eventController.add(
        PlaybackRuntimeMediaAnchor(
          runtimeId: runtimeId ?? runtime.runtimeId,
          loadId: loadId ?? session.loadId,
          seekSequence: sequence,
          anchor: anchor,
        ),
      );
    }

    final version = session.currentSnapshot.snapshotVersion;
    emit(runtimeId: -1);
    emit(loadId: session.loadId - 1);
    expect(samples, isEmpty);
    emit();
    expect(session.currentMediaAnchor, same(anchor));
    expect(session.currentSnapshot.snapshotVersion, version);
    await owner.seek(const Duration(seconds: 2));
    expect(session.currentMediaAnchor, isNull);
    emit();
    expect(samples, [anchor, null]);
    emit(sequence: 1);
    expect(session.currentMediaAnchor, same(anchor));
    final next = session.attach();
    expect(session.currentMediaAnchor, isNull);
    emit(sequence: 1);
    expect(samples, [anchor, null, anchor, null]);
    await subscription.cancel();
    owner.close();
    next.close();
    await runtime.released;
  });
}
