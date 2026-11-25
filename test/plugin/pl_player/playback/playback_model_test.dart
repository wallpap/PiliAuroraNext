import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_source.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

void main() {
  test('归属模型：新页面未加载时旧媒体 EOF 不产生新页面完成动作', () async {
    final runtime = _ModelRuntime();
    final session = PlaybackSession(runtime: runtime);
    final oldOwner = session.attach();
    addTearDown(session.shutdown);
    await oldOwner.load(_plan);
    final oldLoad = session.loadId;
    final nextOwner = session.attach();

    runtime.emit(
      PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: oldLoad,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
    );

    expect(nextOwner.isActive, isTrue);
    expect(session.currentSnapshot.pendingAction, isNull);
    expect(session.currentSnapshot.phase, isNot(PlaybackPhase.ended));
  });

  test('意图模型：旧 writer 抛错不能结算新意图，最新暂停仍须执行', () async {
    final runtime = _ModelRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(session.shutdown);
    await owner.load(_plan);
    final started = Completer<void>();
    final release = Completer<void>();
    runtime.onPlaying = (playing) async {
      if (playing) {
        started.complete();
        await release.future;
        throw StateError('旧播放写入失败');
      }
      return const PlaybackRuntimeCommandResult();
    };

    final old = owner.setPlaying(true);
    await started.future;
    final latest = owner.setPlaying(false);
    expect((await old).outcome, CommandOutcome.superseded);
    release.complete();

    expect((await latest).outcome, CommandOutcome.applied);
    expect(runtime.playCalls, [false, true, false]);
    expect(session.currentSnapshot.intent.playing, isFalse);
  });

  for (final arrival in _EofArrival.values) {
    for (final (position, completes) in [
      (const Duration(milliseconds: 9800), true),
      (const Duration(seconds: 2), false),
    ]) {
      test('EOF 模型：${arrival.name} / ${completes ? '完播' : '提前断流'}', () async {
        final runtime = FakeSessionRuntime();
        final session = PlaybackSession(runtime: runtime);
        final owner = session.attach();
        final opening = Completer<int>();
        final confirmOpen = Completer<void>();
        final writingIntent = Completer<void>();
        final confirmIntent = Completer<void>();
        addTearDown(() async {
          if (!confirmOpen.isCompleted) confirmOpen.complete();
          if (!confirmIntent.isCompleted) confirmIntent.complete();
          await session.shutdown();
        });
        runtime
          ..onLoad = (plan, context, index) async {
            if (index == 0) {
              opening.complete(context.loadId);
              await confirmOpen.future;
            }
            return preparedSessionLoad(context, plan);
          }
          ..onSetPlaying = (playing, _, _) async {
            if (playing && !writingIntent.isCompleted) {
              writingIntent.complete();
              await confirmIntent.future;
            }
            return const PlaybackRuntimeCommandResult();
          };
        final loading = owner.load(
          sessionPlan('eof-model'),
          start: PlaybackStartPolicy.play,
        );
        final firstLoad = await opening.future;
        void deliverEof() {
          runtime.emitActual(
            firstLoad,
            PlaybackActual(
              playing: false,
              position: position,
              duration: const Duration(seconds: 10),
            ),
          );
          final event = PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: firstLoad,
            position: position,
            duration: const Duration(seconds: 10),
          );
          runtime.eventController
            ..add(event)
            ..add(event);
        }

        if (arrival == _EofArrival.beforeOpenReceipt) deliverEof();
        confirmOpen.complete();
        await writingIntent.future;
        if (arrival == _EofArrival.beforeIntentReceipt) deliverEof();
        expect(session.currentSnapshot.pendingAction, isNull);
        confirmIntent.complete();
        final result = await loading;
        expect(result.outcome, LoadOutcome.ready);
        if (arrival == _EofArrival.afterReady) deliverEof();

        if (completes) {
          final ended = session.currentSnapshot;
          expect(ended.phase, PlaybackPhase.ended);
          expect(ended.actual.position, position);
          expect(ended.intent.playing, isFalse);
          expect(session.resumePosition, Duration.zero);
          expect(ended.pendingAction?.ownerId, owner.id);
          expect(runtime.loadedPlans, hasLength(1));
          expect(
            (await owner.acknowledgeAction(ended.pendingAction!)).outcome,
            CommandOutcome.applied,
          );
          deliverEof();
          expect(session.currentSnapshot.pendingAction, isNull);
        } else {
          expect(session.currentSnapshot.pendingAction, isNull);
          expect(session.currentSnapshot.intent.playing, isTrue);
          expect(session.currentSnapshot.phase, isNot(PlaybackPhase.ready));
          await waitForSessionCondition(
            () =>
                runtime.loadedPlans.length == 2 &&
                session.currentSnapshot.phase == PlaybackPhase.ready,
          );
          expect(runtime.loadedPlans.last.reloadPosition, position);
        }
      });
    }
  }

  for (final replaceOwner in [false, true]) {
    test('EOF 模型：意图${replaceOwner ? '被新页面取代' : '写入失败'}不提交已收到的 EOF', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      final writing = Completer<int>();
      final confirm = Completer<void>();
      addTearDown(() async {
        if (!confirm.isCompleted) confirm.complete();
        await session.shutdown();
      });
      runtime.onSetPlaying = (playing, context, _) async {
        if (!playing || writing.isCompleted) {
          return const PlaybackRuntimeCommandResult();
        }
        writing.complete(context.loadId);
        await confirm.future;
        return const PlaybackRuntimeCommandResult(applied: false);
      };
      final loading = owner.load(
        sessionPlan('old-eof-model'),
        start: PlaybackStartPolicy.play,
      );
      final loadId = await writing.future;
      final eof = PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: loadId,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      );
      runtime.eventController.add(eof);
      expect(session.currentSnapshot.pendingAction, isNull);

      if (replaceOwner) {
        final nextOwner = session.attach();
        final nextLoad = nextOwner.load(sessionPlan('new-eof-model'));
        confirm.complete();
        expect((await loading).outcome, LoadOutcome.superseded);
        expect((await nextLoad).outcome, LoadOutcome.ready);
        runtime.eventController.add(eof);
        expect(session.currentSnapshot.phase, PlaybackPhase.ready);
      } else {
        confirm.complete();
        expect((await loading).outcome, LoadOutcome.failed);
        expect(session.currentSnapshot.phase, PlaybackPhase.failed);
      }
      expect(session.currentSnapshot.pendingAction, isNull);
    });
  }

  test('EOF 模型：相同请求重新打开后不消费上一次打开的 EOF', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final opening = Completer<PlaybackExecutionContext>();
    final confirmOpen = Completer<void>();
    final contexts = <PlaybackExecutionContext>[];
    addTearDown(() async {
      if (!confirmOpen.isCompleted) confirmOpen.complete();
      await session.shutdown();
    });
    runtime.onLoad = (plan, context, index) async {
      contexts.add(context);
      if (index == 0) {
        opening.complete(context);
        await confirmOpen.future;
      }
      return preparedSessionLoad(context, plan);
    };

    final loading = owner.load(sessionPlan('eof-reopen'));
    final first = await opening.future;
    runtime.eventController.add(
      PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: first.loadId,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
    );
    expect(
      (await owner.setPlaybackSpeed(1.5)).outcome,
      CommandOutcome.accepted,
    );
    confirmOpen.complete();

    expect((await loading).outcome, LoadOutcome.ready);
    expect(contexts, hasLength(2));
    expect(contexts.last.requestId, first.requestId);
    expect(contexts.last.loadId, isNot(first.loadId));
    expect(session.currentSnapshot.phase, PlaybackPhase.ready);
    expect(session.currentSnapshot.pendingAction, isNull);
  });
}

enum _EofArrival { beforeOpenReceipt, beforeIntentReceipt, afterReady }

final _plan = PlaybackPlan(
  contentKey: 'model-video',
  source: PlaybackSourceSnapshot.fromDataSource(
    NetworkSource(
      videoSource: 'https://example.test/model.mp4',
      audioSource: null,
    ),
  ),
  timeline: const PlaybackTimeline(
    kind: PlaybackTimelineKind.onDemand,
    seekPolicy: PlaybackSeekPolicy.allowed,
    duration: Duration(seconds: 10),
  ),
  configuration: PlaybackConfiguration(),
);

class _ModelRuntime implements PlaybackRuntimePort {
  final _events = StreamController<PlaybackRuntimeEvent>.broadcast(sync: true);
  final _released = Completer<void>();
  final playCalls = <bool>[];
  Future<PlaybackRuntimeCommandResult> Function(bool)? onPlaying;

  @override
  int get runtimeId => 317;

  @override
  Duration? get position => Duration.zero;

  @override
  bool get shaderChangeRequiresRendererReset => false;

  @override
  Stream<PlaybackRuntimeEvent> get events => _events.stream;

  @override
  Future<void> get released => _released.future;

  void emit(PlaybackRuntimeEvent event) => _events.add(event);

  @override
  Future<PlaybackRuntimeLoadResult> load(
    PlaybackPlan plan,
    PlaybackExecutionContext context,
  ) async => PlaybackRuntimeLoadResult(
    loaded: true,
    output: PlaybackOutputPreparation(
      strategy: PlaybackOutputStrategy.prepared,
      evidence: 'model-runtime',
      outputEpoch: context.loadId,
      hasVideo: true,
    ),
  );

  @override
  Future<PlaybackRuntimeCommandResult> setPlaying(
    bool playing,
    PlaybackExecutionContext context,
  ) async {
    playCalls.add(playing);
    return await onPlaying?.call(playing) ??
        const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackShutdownResult> shutdown() async {
    if (!_released.isCompleted) {
      _released.complete();
      unawaited(_events.close());
    }
    return const PlaybackShutdownResult.released();
  }

  // 未被模型事件使用的端口保持显式失败，避免静默模拟原生成功。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
