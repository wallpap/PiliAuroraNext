import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

enum _Input { pause, redirectSeek, replace, close }

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
}
