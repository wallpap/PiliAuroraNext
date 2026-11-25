import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

const _window = Duration(seconds: 15);
const _stallWindow = Duration(seconds: 30);
const _step = Duration(seconds: 1);

enum _Start { load, play, releaseFocus }

enum _Signal {
  none,
  playingFlag,
  buffering,
  advance,
  sampledAdvance,
  staleAdvance,
  eof,
}

enum _Interrupt { none, pause, focus, replace, seek, close }

enum _FailureAt { opening, reconcilingIntent, ready }

void main() {
  const signalPhases = {
    _Signal.none: PlaybackPhase.failed,
    _Signal.playingFlag: PlaybackPhase.failed,
    _Signal.buffering: PlaybackPhase.failed,
    _Signal.advance: PlaybackPhase.ready,
    _Signal.sampledAdvance: PlaybackPhase.ready,
    _Signal.staleAdvance: PlaybackPhase.failed,
    _Signal.eof: PlaybackPhase.ended,
  };
  for (final start in _Start.values) {
    for (final signal in _Signal.values) {
      testWidgets('启动模型：${start.name} × ${signal.name}', (tester) async {
        final model = _Harness(tester);
        try {
          await model.start(start);
          final load = model.session.loadId;
          await model.pump(_window - _step);
          switch (signal) {
            case _Signal.none:
              break;
            case _Signal.playingFlag:
              model.observe(load, playing: true);
            case _Signal.buffering:
              model.observe(load, playing: true, buffering: true);
            case _Signal.advance:
              model.observe(load, playing: true, position: _step * 3);
            case _Signal.sampledAdvance:
              model.observe(load, playing: true);
              model.runtime.position = _step * 3;
            case _Signal.staleAdvance:
              model.observe(
                load,
                playing: true,
                position: _step * 3,
                stale: true,
              );
            case _Signal.eof:
              model.runtime.eventController.add(
                PlaybackRuntimeEnded(
                  runtimeId: model.runtime.runtimeId,
                  loadId: load,
                  position: _step * 10,
                  duration: _step * 10,
                ),
              );
          }
          expect(
            model.phase,
            signal == _Signal.eof ? PlaybackPhase.ended : PlaybackPhase.ready,
          );
          if (signal == _Signal.playingFlag || signal == _Signal.buffering) {
            model.observe(
              load,
              playing: true,
              buffering: signal == _Signal.buffering,
            );
          }
          await model.pump(_step);
          expect(model.phase, signalPhases[signal]);
          if (model.phase == PlaybackPhase.failed) {
            expect(
              model.session.currentSnapshot.failure?.operation,
              'observe-playback-start',
            );
            expect(model.session.currentSnapshot.intent.playing, isTrue);
          }
          if (signal == _Signal.advance || signal == _Signal.sampledAdvance) {
            await model.pump(_window);
            expect(model.phase, PlaybackPhase.ready);
          }
        } finally {
          await model.close();
        }
      });
    }
  }

  for (final advancesAfterSeek in [false, true]) {
    testWidgets('启动模型：seek 落点不等于播放推进，后续推进=$advancesAfterSeek', (tester) async {
      final runtime = GatedSessionRuntime()..position = Duration.zero;
      final model = _Harness(tester, runtime: runtime);
      try {
        await model.start(_Start.load);
        model.observe(model.session.loadId, playing: true, position: _step * 4);
        runtime.unblock();
        model.observe(model.session.loadId, playing: true, position: _step * 4);
        if (advancesAfterSeek) {
          model.observe(
            model.session.loadId,
            playing: true,
            position: _step * 5,
          );
        }
        await model.pump(_window);
        expect(
          model.phase,
          advancesAfterSeek ? PlaybackPhase.ready : PlaybackPhase.failed,
        );
      } finally {
        await model.close();
        unawaited(runtime.changes.close());
      }
    });
  }

  const interruptPhases = {
    _Interrupt.none: PlaybackPhase.failed,
    _Interrupt.pause: PlaybackPhase.ready,
    _Interrupt.focus: PlaybackPhase.ready,
    _Interrupt.replace: PlaybackPhase.ready,
    _Interrupt.seek: PlaybackPhase.ready,
    _Interrupt.close: PlaybackPhase.disposed,
  };
  for (final interrupt in _Interrupt.values) {
    testWidgets('启动模型：临界时刻 ${interrupt.name}', (tester) async {
      final model = _Harness(tester);
      try {
        await model.start(_Start.load);
        await model.pump(_window - _step);
        switch (interrupt) {
          case _Interrupt.none:
            expect(
              (await model.owner.setPlaying(true)).outcome,
              CommandOutcome.applied,
            );
          case _Interrupt.pause:
            expect(
              (await model.owner.setPlaying(false)).outcome,
              CommandOutcome.applied,
            );
          case _Interrupt.focus:
            expect(
              model.session.acquireSessionInhibitor(
                PlaybackInhibitorSource.audioFocus,
              ),
              isNotNull,
            );
          case _Interrupt.replace:
            await model.session.attach().load(
              sessionPlan('replacement'),
              start: PlaybackStartPolicy.play,
            );
          case _Interrupt.seek:
            model.runtime.onSeek = (position, context) async {
              model.observe(context.loadId, playing: true, position: position);
              return const PlaybackRuntimeCommandResult();
            };
            expect(
              (await model.owner.seek(_step * 4)).outcome,
              CommandOutcome.applied,
            );
          case _Interrupt.close:
            await model.close();
        }
        await model.pump(_step);
        expect(model.phase, interruptPhases[interrupt]);
        if (interrupt == _Interrupt.replace || interrupt == _Interrupt.seek) {
          await model.pump(_window - _step);
          expect(model.phase, PlaybackPhase.failed);
        }
      } finally {
        await model.close();
      }
    });
  }

  for (final automatic in [false, true]) {
    testWidgets('启动模型：${automatic ? '时限内恢复' : '超时后重试'}使用新加载的观察窗口', (
      tester,
    ) async {
      final model = _Harness(tester);
      try {
        await model.start(_Start.load);
        final previousLoad = model.session.loadId;
        await model.pump(automatic ? _window - _step : _window);
        expect(
          model.phase,
          automatic ? PlaybackPhase.ready : PlaybackPhase.failed,
        );

        final receipt = automatic
            ? await model.owner.recover(sessionPlan('startup'))
            : await model.owner.retry();
        expect(receipt.outcome, LoadOutcome.ready);
        expect(model.session.loadId, greaterThan(previousLoad));
        expect(model.session.currentSnapshot.failure, isNull);
        await model.pump(_step);
        expect(model.phase, PlaybackPhase.ready);
        model.observe(model.session.loadId, playing: true, position: _step);
        await model.pump(_window);
        expect(model.phase, PlaybackPhase.ready);
      } finally {
        await model.close();
      }
    });
  }

  for (final interruption in ['none', 'buffering', 'pause', 'newLoad']) {
    testWidgets('持续推进模型：首次推进后 $interruption', (tester) async {
      final model = _Harness(tester);
      try {
        await model.start(_Start.load);
        await model.pump(_step);
        model.observe(model.session.loadId, playing: true, position: _step);
        await model.pump(_stallWindow - _step);
        expect(model.phase, PlaybackPhase.ready);
        switch (interruption) {
          case 'buffering':
            model.observe(
              model.session.loadId,
              playing: true,
              buffering: true,
              position: _step,
            );
          case 'pause':
            await model.owner.setPlaying(false);
          case 'newLoad':
            await model.owner.load(sessionPlan('new-media'));
        }
        await model.pump(_step);
        if (interruption == 'none' || interruption == 'buffering') {
          expect(model.phase, PlaybackPhase.failed);
          expect(
            model.session.currentSnapshot.failure?.operation,
            'observe-playback-stall',
          );
        } else {
          expect(model.phase, PlaybackPhase.ready);
        }
      } finally {
        await model.close();
      }
    });
  }

  testWidgets('持续推进模型：只在临界时读取到新位置仍续期', (tester) async {
    final model = _Harness(tester);
    try {
      await model.start(_Start.load);
      final load = model.session.loadId;
      await model.pump(_step);
      model.observe(load, playing: true, position: _step);
      await model.pump(_stallWindow - _step);
      model.runtime.position = _step * 2;
      await model.pump(_step);
      expect(model.phase, PlaybackPhase.ready);
      await model.pump(_stallWindow - _step);
      expect(model.phase, PlaybackPhase.ready);
      await model.pump(_step);
      expect(model.phase, PlaybackPhase.failed);
    } finally {
      await model.close();
    }
  });

  for (final stage in _FailureAt.values) {
    test('结算模型：${stage.name} 的原生失败不可被成功回执覆盖', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      final blocked = Completer<int>();
      final reply = Completer<void>();
      final pausedAfterFailure = Completer<void>();
      addTearDown(() async {
        if (!reply.isCompleted) reply.complete();
        await session.shutdown();
      });
      runtime
        ..onLoad = (plan, context, _) async {
          if (stage == _FailureAt.opening) {
            blocked.complete(context.loadId);
            await reply.future;
          }
          return preparedSessionLoad(context, plan);
        }
        ..onSetPlaying = (playing, context, _) async {
          if (!playing && !pausedAfterFailure.isCompleted) {
            pausedAfterFailure.complete();
          }
          if (playing &&
              stage == _FailureAt.reconcilingIntent &&
              !blocked.isCompleted) {
            blocked.complete(context.loadId);
            await reply.future;
          }
          return const PlaybackRuntimeCommandResult();
        };
      final loading = owner.load(
        sessionPlan('terminal'),
        start: PlaybackStartPolicy.play,
      );
      LoadResult? settled;
      unawaited(loading.then((receipt) => settled = receipt));
      final loadId = stage == _FailureAt.ready
          ? (await loading).loadId!
          : await blocked.future;
      const failure = PlaybackFailure(
        category: PlaybackFailureCategory.source,
        operation: 'native-end-file',
        stage: PlaybackStage.observing,
        recoverable: true,
        cause: 'fixture native failure',
      );
      runtime.eventController.add(
        PlaybackRuntimeFailure(
          runtimeId: runtime.runtimeId,
          loadId: loadId,
          failure: failure,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      if (stage != _FailureAt.ready) {
        expect(settled?.outcome, LoadOutcome.failed);
        expect(settled?.failure, same(failure));
      }
      reply.complete();
      final receipt = await loading;
      if (stage == _FailureAt.ready) {
        expect(receipt.outcome, LoadOutcome.ready);
      }
      await session.drained;
      if (stage != _FailureAt.opening) {
        await waitForSessionCondition(() => pausedAfterFailure.isCompleted);
      }
      expect(session.currentSnapshot.phase, PlaybackPhase.failed);
      expect(session.currentSnapshot.failure, same(failure));
    });
  }
}

class _Harness {
  _Harness(this.tester, {FakeSessionRuntime? runtime})
    : runtime = runtime ?? (FakeSessionRuntime()..position = Duration.zero) {
    session = PlaybackSession(runtime: this.runtime, monotonicNow: () => now);
    owner = session.attach();
  }

  final WidgetTester tester;
  final FakeSessionRuntime runtime;
  late final PlaybackSession session;
  late final PlaybackOwner owner;
  Duration now = Duration.zero;

  PlaybackPhase get phase => session.currentSnapshot.phase;

  Future<void> pump(Duration elapsed) {
    now += elapsed;
    return tester.pump(elapsed);
  }

  Future<void> start(_Start start) async {
    final focus = start == _Start.releaseFocus
        ? session.acquireSessionInhibitor(PlaybackInhibitorSource.audioFocus)
        : null;
    final receipt = await owner.load(
      sessionPlan('startup'),
      start: start == _Start.play
          ? PlaybackStartPolicy.pause
          : PlaybackStartPolicy.play,
    );
    expect(receipt.outcome, LoadOutcome.ready);
    if (start == _Start.play) {
      expect((await owner.setPlaying(true)).outcome, CommandOutcome.applied);
    }
    if (focus != null) {
      await pump(_window);
      expect(phase, PlaybackPhase.ready);
      expect(
        (await session.releaseSessionInhibitor(focus)).outcome,
        CommandOutcome.applied,
      );
    }
    expect(phase, PlaybackPhase.ready);
  }

  void observe(
    int load, {
    required bool playing,
    bool buffering = false,
    Duration position = Duration.zero,
    bool stale = false,
  }) {
    final actual = PlaybackActual(
      playing: playing,
      buffering: buffering,
      position: position,
    );
    if (stale) {
      runtime.eventController.add(
        PlaybackRuntimeStateChanged(
          runtimeId: runtime.runtimeId,
          loadId: load - 1,
          actual: actual,
        ),
      );
    } else {
      runtime.emitActual(load, actual);
    }
  }

  Future<void> close() async {
    final shutdown = session.shutdown();
    await tester.pump();
    await shutdown;
  }
}
