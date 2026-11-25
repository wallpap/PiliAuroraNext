import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

enum _Input { pause, redirectSeek, replace, close }

enum _LoadReply { resolver, predicate, open, intent, nativeFailure }

enum _RecoveryHandoff { resolving, replaced, ownerChanged }

Iterable<List<_Input>> _orders(List<_Input> remaining) sync* {
  if (remaining.isEmpty) {
    yield const [];
    return;
  }
  for (final next in remaining) {
    for (final tail in _orders(
      remaining.where((input) => input != next).toList(),
    )) {
      yield [next, ...tail];
    }
  }
}

const _failure = PlaybackFailure(
  category: PlaybackFailureCategory.source,
  operation: 'native-failure',
  stage: PlaybackStage.observing,
  recoverable: false,
  cause: 'fixture failure',
);
const _cleanupFailure = PlaybackFailure(
  category: PlaybackFailureCategory.disposal,
  operation: 'fixture-cleanup',
  stage: PlaybackStage.closing,
  recoverable: false,
  cause: 'fixture cleanup failure',
);
const _firstTarget = Duration(seconds: 1);
const _nextTarget = Duration(seconds: 2);
const _duration = Duration(seconds: 10);

void _emitTerminal(FakeSessionRuntime runtime, int load, {required bool eof}) {
  runtime.eventController.add(
    eof
        ? PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: load,
            position: _duration,
            duration: _duration,
          )
        : PlaybackRuntimeFailure(
            runtimeId: runtime.runtimeId,
            loadId: load,
            failure: _failure,
          ),
  );
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  for (final handoff in _RecoveryHandoff.values) {
    test('旧媒体的自动恢复不能跨过交接：${handoff.name}', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final originalOwner = session.attach();
      final original = sessionPlan('recovery-old');
      final next = sessionPlan('recovery-next');
      final resolver = Completer<PlaybackPlan?>();
      try {
        expect(
          (await originalOwner.load(
            original,
            start: PlaybackStartPolicy.play,
          )).outcome,
          LoadOutcome.ready,
        );
        var owner = originalOwner;
        Future<LoadResult>? replacement;
        switch (handoff) {
          case _RecoveryHandoff.resolving:
            replacement = owner.query((_) => resolver.future);
          case _RecoveryHandoff.replaced:
            expect((await owner.load(next)).outcome, LoadOutcome.ready);
          case _RecoveryHandoff.ownerChanged:
            owner = session.attach();
        }
        await _turn();
        final revision = session.revision;
        final loadId = session.loadId;
        final snapshot = session.currentSnapshot;
        expect((await owner.recover(original)).outcome, LoadOutcome.superseded);
        expect(session.revision, revision);
        expect(session.loadId, loadId);
        expect(session.currentSnapshot, same(snapshot));
        if (replacement != null) {
          resolver.complete(next);
          expect((await replacement).outcome, LoadOutcome.ready);
        }
        expect(runtime.loadedKeys, [
          original.contentKey,
          if (handoff != _RecoveryHandoff.ownerChanged) next.contentKey,
        ]);
      } finally {
        if (!resolver.isCompleted) resolver.complete(null);
        await session.shutdown();
      }
    });
  }

  for (final cleanup in ['pending', 'incomplete', 'error']) {
    testWidgets('先收到实际释放，再处理关闭回执 $cleanup', (tester) async {
      const budget = Duration(seconds: 2);
      final cleanupReply = Completer<PlaybackShutdownResult>();
      final runtime = FakeSessionRuntime()
        ..onShutdown = () => cleanupReply.future;
      final session = PlaybackSession(runtime: runtime, shutdownBudget: budget);
      final owner = session.attach();
      try {
        await owner.load(sessionPlan('shutdown-release-first'));
        PlaybackShutdownResult? receipt;
        final shutdown = session.shutdown()..then((result) => receipt = result);
        runtime.completeRelease();
        await tester.pump();
        expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
        expect(receipt?.outcome, PlaybackShutdownOutcome.released);

        switch (cleanup) {
          case 'incomplete':
            cleanupReply.complete(
              const PlaybackShutdownResult.cleanupIncomplete(_cleanupFailure),
            );
          case 'error':
            cleanupReply.completeError(StateError('fixture late cleanup'));
        }
        await tester.pump(budget);
        expect((await shutdown).outcome, PlaybackShutdownOutcome.released);
        expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
        expect(session.currentSnapshot.failure, isNull);
      } finally {
        if (!cleanupReply.isCompleted) {
          cleanupReply.complete(const PlaybackShutdownResult.released());
        }
        await tester.pump();
        await runtime.eventController.close();
      }
    });
  }

  test('关闭重入共享真实收据，清理成功仍须等实际释放', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final cleanupReply = Completer<PlaybackShutdownResult>();
    Future<PlaybackShutdownResult>? reentrant;
    runtime.onShutdown = () {
      reentrant = session.shutdown();
      return cleanupReply.future;
    };
    try {
      final shutdown = session.shutdown();
      expect(reentrant, same(shutdown));
      var settled = false;
      unawaited(shutdown.then((_) => settled = true));
      cleanupReply.complete(const PlaybackShutdownResult.released());
      await _turn();
      expect(settled, isFalse);
      expect(session.currentSnapshot.phase, PlaybackPhase.closing);
      runtime.completeRelease();
      expect((await shutdown).outcome, PlaybackShutdownOutcome.released);
      expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
    } finally {
      if (!cleanupReply.isCompleted) {
        cleanupReply.complete(const PlaybackShutdownResult.released());
      }
      runtime.completeRelease();
      await session.shutdown();
      await runtime.eventController.close();
    }
  });

  testWidgets('关闭超时收据固定，真实释放仍推进会话终态', (tester) async {
    const budget = Duration(seconds: 2);
    final cleanupReply = Completer<PlaybackShutdownResult>();
    final runtime = FakeSessionRuntime()
      ..onShutdown = () => cleanupReply.future;
    final session = PlaybackSession(runtime: runtime, shutdownBudget: budget);
    try {
      final shutdown = session.shutdown();
      await tester.pump(budget);
      final result = await shutdown;
      expect(result.outcome, PlaybackShutdownOutcome.cleanupIncomplete);
      expect(result.failure?.category, PlaybackFailureCategory.timeout);
      expect(session.currentSnapshot.failure, same(result.failure));

      runtime.completeRelease();
      await tester.pump();
      cleanupReply.complete(
        const PlaybackShutdownResult.cleanupIncomplete(_cleanupFailure),
      );
      await tester.pump();
      expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
      expect(session.currentSnapshot.failure, isNull);
      expect(await shutdown, same(result));
    } finally {
      if (!cleanupReply.isCompleted) {
        cleanupReply.complete(const PlaybackShutdownResult.released());
      }
      runtime.completeRelease();
      await tester.pump();
      await runtime.eventController.close();
    }
  });

  for (final offsetMs in [-1, 0, 1]) {
    test('关闭释放按单调截止时间结算：偏移 ${offsetMs}ms', () async {
      const budget = Duration(seconds: 2);
      var now = Duration.zero;
      final cleanupReply = Completer<PlaybackShutdownResult>();
      final runtime = FakeSessionRuntime()
        ..onShutdown = () => cleanupReply.future;
      final session = PlaybackSession(
        runtime: runtime,
        shutdownBudget: budget,
        monotonicNow: () => now,
      );
      try {
        final shutdown = session.shutdown();
        now = budget + Duration(milliseconds: offsetMs);
        runtime.completeRelease();
        final outcome = await shutdown;

        expect(
          outcome.outcome,
          offsetMs < 0
              ? PlaybackShutdownOutcome.released
              : PlaybackShutdownOutcome.cleanupIncomplete,
        );
        if (offsetMs >= 0) {
          expect(outcome.failure?.category, PlaybackFailureCategory.timeout);
        }
        expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
        expect(session.currentSnapshot.failure, isNull);
      } finally {
        cleanupReply.complete(const PlaybackShutdownResult.released());
        await runtime.eventController.close();
      }
    });
  }

  for (final reply in _LoadReply.values) {
    for (final offsetMs in [-1, 0, 1]) {
      testWidgets('加载回执与截止时间：${reply.name} 偏移 ${offsetMs}ms', (
        tester,
      ) async {
        const budget = Duration(seconds: 2);
        var now = Duration.zero;
        final blocked = Completer<int>();
        final resume = Completer<void>();
        final plan = sessionPlan('deadline');
        final runtime = FakeSessionRuntime()
          ..onLoad = (plan, context, _) async {
            if (reply == _LoadReply.open || reply == _LoadReply.nativeFailure) {
              blocked.complete(context.loadId);
              await resume.future;
            }
            return preparedSessionLoad(context, plan);
          }
          ..onSetPlaying = (playing, context, _) async {
            if (playing && reply == _LoadReply.intent) {
              blocked.complete(context.loadId);
              await resume.future;
            }
            return const PlaybackRuntimeCommandResult();
          };
        final session = PlaybackSession(
          runtime: runtime,
          loadBudget: budget,
          monotonicNow: () => now,
        );
        final owner = session.attach();
        final receiptTime = budget + Duration(milliseconds: offsetMs);
        try {
          final fromQuery =
              reply == _LoadReply.resolver || reply == _LoadReply.predicate;
          final load = fromQuery
              ? owner.query(
                  (_) async {
                    blocked.complete(0);
                    await resume.future;
                    return plan;
                  },
                  start: PlaybackStartPolicy.play,
                  shouldLoad: reply == _LoadReply.predicate
                      ? () {
                          now = receiptTime;
                          return false;
                        }
                      : null,
                )
              : owner.load(plan, start: PlaybackStartPolicy.play);
          LoadResult? receipt;
          unawaited(load.then((result) => receipt = result));
          final loadId = await blocked.future;
          if (reply != _LoadReply.predicate) now = receiptTime;
          if (reply == _LoadReply.nativeFailure) {
            _emitTerminal(runtime, loadId, eof: false);
          }
          resume.complete();
          await tester.pump();

          final beforeDeadline = offsetMs < 0;
          final expected = !beforeDeadline || reply == _LoadReply.nativeFailure
              ? LoadOutcome.failed
              : reply == _LoadReply.predicate
              ? LoadOutcome.noMedia
              : LoadOutcome.ready;
          expect(
            receipt?.outcome,
            expected,
          );
          expect(
            receipt?.failure?.category,
            expected != LoadOutcome.failed
                ? null
                : beforeDeadline
                ? _failure.category
                : PlaybackFailureCategory.timeout,
          );
          expect(
            session.currentSnapshot.phase,
            switch (expected) {
              LoadOutcome.ready => PlaybackPhase.ready,
              LoadOutcome.noMedia => PlaybackPhase.idle,
              _ => PlaybackPhase.failed,
            },
          );
          expect(session.currentSnapshot.failure, same(receipt?.failure));
          if (fromQuery && expected != LoadOutcome.ready) {
            expect(runtime.loadedKeys, isEmpty);
          }
        } finally {
          if (!resume.isCompleted) resume.complete();
          final shutdown = session.shutdown();
          await tester.pump();
          await shutdown;
        }
      });
    }
  }

  for (final eofFirst in [false, true]) {
    test('当前加载的失败与完播按首个终态结算 EOF 先到=$eofFirst', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      addTearDown(session.shutdown);
      final first = await owner.load(
        sessionPlan('terminal-order'),
        start: PlaybackStartPolicy.play,
      );

      _emitTerminal(runtime, first.loadId!, eof: eofFirst);
      final terminal = session.currentSnapshot;
      _emitTerminal(runtime, first.loadId!, eof: !eofFirst);
      _emitTerminal(runtime, first.loadId!, eof: eofFirst);
      expect(session.currentSnapshot, same(terminal));
      if (eofFirst) {
        expect(terminal.phase, PlaybackPhase.ended);
        expect(terminal.actual.position, _duration);
        expect(terminal.pendingAction?.kind, PlaybackActionKind.completed);
        expect(terminal.failure, isNull);
        expect(session.resumePosition, Duration.zero);
        expect(
          (await owner.acknowledgeAction(terminal.pendingAction!)).outcome,
          CommandOutcome.applied,
        );
        _emitTerminal(runtime, first.loadId!, eof: false);
        expect(session.currentSnapshot.phase, PlaybackPhase.ended);
        expect(session.currentSnapshot.pendingAction, isNull);
        expect((await owner.setPlaying(true)).outcome, CommandOutcome.applied);
      } else {
        expect(terminal.phase, PlaybackPhase.failed);
        expect(terminal.failure, same(_failure));
        expect(terminal.pendingAction, isNull);
        expect((await owner.retry()).outcome, LoadOutcome.ready);
      }
      expect(session.currentSnapshot.phase, PlaybackPhase.ready);
      expect(session.currentSnapshot.loadId, isNot(first.loadId));
    });
  }

  for (final closeDuringSeek in [false, true]) {
    for (final order in _orders([
      _Input.pause,
      _Input.redirectSeek,
      _Input.replace,
      if (closeDuringSeek) _Input.close,
    ])) {
      test('交错模型 ${order.map((input) => input.name).join(' → ')}', () async {
        final nativeReply = Completer<void>();
        final seekStarted = Completer<PlaybackExecutionContext>();
        final runtime = FakeSessionRuntime();
        final session = PlaybackSession(runtime: runtime);
        final owner = session.attach();
        final opened = await owner.load(
          sessionPlan('initial'),
          start: PlaybackStartPolicy.play,
        );
        final oldLoad = opened.loadId!;
        runtime
          ..onSeek = (target, context) async {
            if (target == _firstTarget) {
              seekStarted.complete(context);
              await nativeReply.future;
            }
            return PlaybackRuntimeCommandResult(applied: context.isCurrent());
          }
          ..onSetPlaying = (_, context, _) async {
            await nativeReply.future;
            return PlaybackRuntimeCommandResult(applied: context.isCurrent());
          }
          ..onShutdown = () async {
            await nativeReply.future;
            runtime.completeRelease();
            await runtime.eventController.close();
            return const PlaybackShutdownResult.released();
          };
        addTearDown(() async {
          if (!nativeReply.isCompleted) nativeReply.complete();
          await session.shutdown();
        });
        CommandResult? initialReceipt;
        unawaited(
          owner.seek(_firstTarget).then((result) => initialReceipt = result),
        );
        final initialContext = await seekStarted.future;

        final nextReceipts = <_Input, CommandOutcome>{};
        LoadResult? replacement;
        PlaybackShutdownResult? closed;
        for (final input in order) {
          switch (input) {
            case _Input.pause:
              unawaited(
                owner.setPlaying(false).then((result) {
                  nextReceipts[input] = result.outcome;
                }),
              );
            case _Input.redirectSeek:
              unawaited(
                owner.seek(_nextTarget).then((result) {
                  nextReceipts[input] = result.outcome;
                }),
              );
            case _Input.replace:
              unawaited(
                owner.load(sessionPlan('replacement')).then((result) {
                  replacement = result;
                }),
              );
            case _Input.close:
              unawaited(session.shutdown().then((result) => closed = result));
          }
          await _turn();
          expect(runtime.loadedKeys, ['initial']);
          expect(runtime.seekCalls, [_firstTarget]);
        }
        final closeAt = order.indexOf(_Input.close);
        final replaceAt = order.indexOf(_Input.replace);
        final seekAt = order.indexOf(_Input.redirectSeek);
        final pauseAt = order.indexOf(_Input.pause);
        final replaceAccepted = !closeDuringSeek || replaceAt < closeAt;
        final firstInvalidation = order.firstWhere(
          (input) => input != _Input.pause,
        );
        expect(initialContext.isCurrent(), isFalse);
        expect(
          initialReceipt?.outcome,
          firstInvalidation == _Input.close
              ? CommandOutcome.closed
              : CommandOutcome.superseded,
        );
        expect(
          nextReceipts[_Input.pause],
          closeDuringSeek && closeAt < pauseAt
              ? CommandOutcome.closed
              : replaceAt < pauseAt
              ? CommandOutcome.accepted
              : replaceAccepted
              ? CommandOutcome.superseded
              : CommandOutcome.closed,
        );
        expect(
          nextReceipts[_Input.redirectSeek],
          closeDuringSeek && closeAt < seekAt
              ? CommandOutcome.closed
              : replaceAt < seekAt
              ? CommandOutcome.notReady
              : replaceAccepted
              ? CommandOutcome.superseded
              : CommandOutcome.closed,
        );
        if (closeDuringSeek) {
          expect(
            replacement?.outcome,
            replaceAccepted ? LoadOutcome.superseded : LoadOutcome.closed,
          );
          expect(session.currentSnapshot.phase, PlaybackPhase.closing);
          expect(closed, isNull);
        } else {
          expect(replacement, isNull);
          expect(session.currentSnapshot.phase, PlaybackPhase.loading);
        }
        _emitTerminal(runtime, oldLoad, eof: true);
        _emitTerminal(runtime, oldLoad, eof: false);
        expect(session.currentSnapshot.pendingAction, isNull);
        expect(session.currentSnapshot.failure, isNull);

        nativeReply.complete();
        await _turn();
        if (closeDuringSeek) {
          expect(closed?.outcome, PlaybackShutdownOutcome.released);
          expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
          expect(runtime.loadedKeys, ['initial']);
        } else {
          expect(replacement?.outcome, LoadOutcome.ready);
          expect(runtime.loadedKeys, ['initial', 'replacement']);
          _emitTerminal(runtime, oldLoad, eof: false);
          _emitTerminal(runtime, oldLoad, eof: true);
          expect(session.currentSnapshot.loadId, replacement?.loadId);
          expect(session.currentSnapshot.phase, PlaybackPhase.ready);
          expect(session.currentSnapshot.intent.playing, isFalse);
          expect(session.currentSnapshot.pendingAction, isNull);
          expect(session.currentSnapshot.failure, isNull);
        }
      });
    }
  }

  for (final eof in [false, true]) {
    for (final submitted in [false, true]) {
      test('终态取消跳转 EOF=$eof，已提交=$submitted', () async {
        final runtime = GatedSessionRuntime();
        final nativeReply = Completer<PlaybackRuntimeCommandResult>();
        if (submitted) runtime.unblock();
        runtime.onSeek = (_, _) => nativeReply.future;
        final session = PlaybackSession(runtime: runtime);
        final owner = session.attach();
        addTearDown(() async {
          if (!nativeReply.isCompleted) {
            nativeReply.complete(const PlaybackRuntimeCommandResult());
          }
          await session.shutdown();
          await runtime.changes.close();
        });
        final opened = await owner.load(sessionPlan('terminal-seek'));
        CommandResult? seekReceipt;
        unawaited(
          owner.seek(_firstTarget).then((result) => seekReceipt = result),
        );
        await _turn();
        expect(runtime.seekCalls, submitted ? [_firstTarget] : isEmpty);
        expect(seekReceipt, isNull);

        final phase = eof ? PlaybackPhase.ended : PlaybackPhase.failed;
        _emitTerminal(runtime, opened.loadId!, eof: eof);
        await _turn();
        expect(session.currentSnapshot.phase, phase);
        expect(seekReceipt?.outcome, CommandOutcome.superseded);
        expect(runtime.changes.hasListener, isFalse);

        nativeReply.complete(const PlaybackRuntimeCommandResult());
        await _turn();
        expect(session.currentSnapshot.phase, phase);
      });
    }
  }

  test('新跳转等待原生资格时，已提交的旧跳转也立即失效', () async {
    final runtime = GatedSessionRuntime()..unblock();
    final nativeReply = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSeek = (target, _) {
      if (target == _firstTarget) {
        runtime.blocked = true;
        return nativeReply.future;
      }
      return Future.value(const PlaybackRuntimeCommandResult());
    };
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(() async {
      if (!nativeReply.isCompleted) {
        nativeReply.complete(const PlaybackRuntimeCommandResult());
      }
      await session.shutdown();
      await runtime.changes.close();
    });
    await owner.load(sessionPlan('redirect'));
    CommandResult? firstReceipt;
    unawaited(owner.seek(_firstTarget).then((result) => firstReceipt = result));
    await _turn();
    final second = owner.seek(_nextTarget);
    await _turn();
    expect(firstReceipt?.outcome, CommandOutcome.superseded);
    expect(runtime.seekCalls, [_firstTarget]);

    runtime.unblock();
    await _turn();
    expect(runtime.seekCalls, [_firstTarget]);
    nativeReply.complete(const PlaybackRuntimeCommandResult());
    expect((await second).outcome, CommandOutcome.applied);
    expect(runtime.seekCalls, [_firstTarget, _nextTarget]);
  });

  test('旧原生 play 未返回时，重复 pause 必须等待最新暂停落实', () async {
    final nativePlay = Completer<PlaybackRuntimeCommandResult>();
    final writes = <bool>[];
    final runtime = FakeSessionRuntime()
      ..onSetPlaying = (playing, context, _) async {
        writes.add(playing);
        if (playing) return nativePlay.future;
        return const PlaybackRuntimeCommandResult();
      };
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(() async {
      if (!nativePlay.isCompleted) {
        nativePlay.complete(const PlaybackRuntimeCommandResult());
      }
      await session.shutdown();
    });
    final opened = await owner.load(sessionPlan('repeated-pause'));
    runtime.emitActual(opened.loadId!, const PlaybackActual(playing: false));
    final play = owner.setPlaying(true);
    expect(writes, [false, true]);
    final pause = owner.setPlaying(false);
    CommandResult? lastReceipt;
    final repeatedPause = owner.setPlaying(false)
      ..then((result) => lastReceipt = result);
    await _turn();
    expect((await play).outcome, CommandOutcome.superseded);
    expect((await pause).outcome, CommandOutcome.superseded);
    expect(lastReceipt, isNull);

    nativePlay.complete(const PlaybackRuntimeCommandResult());
    expect((await repeatedPause).outcome, CommandOutcome.applied);
    expect(writes, [false, true, false]);
  });

  for (final sessionScope in [false, true]) {
    testWidgets('解除抑制有独立命令时限 sessionScope=$sessionScope', (
      tester,
    ) async {
      const budget = Duration(seconds: 2);
      final nativePause = Completer<PlaybackRuntimeCommandResult>();
      final writes = <bool>[];
      final runtime = FakeSessionRuntime()
        ..onSetPlaying = (playing, _, _) async {
          writes.add(playing);
          if (!playing) return nativePause.future;
          return const PlaybackRuntimeCommandResult();
        };
      final session = PlaybackSession(runtime: runtime, commandBudget: budget);
      final owner = session.attach();
      try {
        final opened = await owner.load(
          sessionPlan('release-timeout'),
          start: PlaybackStartPolicy.play,
        );
        runtime.emitActual(opened.loadId!, const PlaybackActual(playing: true));
        final token = sessionScope
            ? session.acquireSessionInhibitor(
                PlaybackInhibitorSource.audioFocus,
              )!
            : owner.acquireInhibitor(PlaybackInhibitorSource.system)!;
        expect(writes, [true, false]);

        CommandResult? releaseReceipt;
        final release = sessionScope
            ? session.releaseSessionInhibitor(token)
            : owner.releaseInhibitor(token);
        unawaited(release.then((result) => releaseReceipt = result));
        await tester.pump(budget);
        expect(releaseReceipt?.outcome, CommandOutcome.failed);
        expect(
          releaseReceipt?.failure?.category,
          PlaybackFailureCategory.timeout,
        );
        expect(writes, [true, false]);

        nativePause.complete(const PlaybackRuntimeCommandResult());
        await tester.pump();
        expect(writes, [true, false, true]);
        expect(session.currentSnapshot.intent.playing, isTrue);
        expect(session.currentSnapshot.inhibitors, isEmpty);
      } finally {
        if (!nativePause.isCompleted) {
          nativePause.complete(const PlaybackRuntimeCommandResult());
        }
        final shutdown = session.shutdown();
        await tester.pump();
        await shutdown;
      }
    });
  }

  for (final offsetMs in [-1, 0, 1]) {
    testWidgets('连续切源与在途 seek 回执的截止时间偏移 ${offsetMs}ms', (
      tester,
    ) async {
      const budget = Duration(seconds: 2);
      var now = Duration.zero;
      final nativeSeek = Completer<PlaybackRuntimeCommandResult>();
      final runtime = FakeSessionRuntime()
        ..onSeek = (_, _) => nativeSeek.future;
      final session = PlaybackSession(
        runtime: runtime,
        loadBudget: budget,
        monotonicNow: () => now,
      );
      final owner = session.attach();
      try {
        final initial = await owner.load(sessionPlan('initial'));
        final seek = owner.seek(_firstTarget);
        expect(runtime.seekCalls, [_firstTarget]);
        final middle = owner.load(sessionPlan('middle'));
        LoadResult? receipt;
        final latest = owner.load(sessionPlan('latest'))
          ..then((result) => receipt = result);
        expect((await seek).outcome, CommandOutcome.superseded);
        expect((await middle).outcome, LoadOutcome.superseded);
        _emitTerminal(runtime, initial.loadId!, eof: true);

        now = budget + Duration(milliseconds: offsetMs);
        await tester.pump(now);
        expect(runtime.loadedKeys, ['initial']);
        if (offsetMs < 0) {
          expect(receipt, isNull);
        } else {
          expect(receipt?.outcome, LoadOutcome.failed);
          expect(receipt?.failure?.category, PlaybackFailureCategory.timeout);
        }

        nativeSeek.complete(const PlaybackRuntimeCommandResult());
        await tester.pump();
        final result = await latest;
        if (offsetMs < 0) {
          expect(result.outcome, LoadOutcome.ready);
          expect(runtime.loadedKeys, ['initial', 'latest']);
          expect(session.currentSnapshot.loadId, result.loadId);
          expect(session.currentSnapshot.phase, PlaybackPhase.ready);
        } else {
          expect(result.outcome, LoadOutcome.failed);
          expect(runtime.loadedKeys, ['initial']);
          expect(session.currentSnapshot.phase, PlaybackPhase.failed);
          expect(session.currentSnapshot.failure, same(result.failure));
        }
        expect(session.currentSnapshot.pendingAction, isNull);
      } finally {
        if (!nativeSeek.isCompleted) {
          nativeSeek.complete(const PlaybackRuntimeCommandResult());
        }
        final shutdown = session.shutdown();
        await tester.pump();
        await shutdown;
      }
    });
  }
}
