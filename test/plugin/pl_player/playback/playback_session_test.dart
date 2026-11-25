import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/background_policy.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';

import 'playback_session_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('进度归属需要当前 owner 及已确认的内容', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    addTearDown(session.shutdown);
    final first = session.attach();
    final initial = await first.load(sessionPlan('file:1'));
    expect(first.ownsLoadedContent('file:1'), isTrue);
    expect(first.ownsLoadedContent('file:2'), isFalse);
    runtime.eventController.add(
      PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: initial.loadId,
        position: const Duration(seconds: 10),
      ),
    );
    expect(session.currentSnapshot.phase, PlaybackPhase.ended);
    expect(first.ownsLoadedContent('file:1'), isTrue);

    final pending = Completer<void>();
    runtime.onLoad = (_, context, _) async {
      await pending.future;
      return failedSessionLoad(context);
    };
    final replacing = first.load(sessionPlan('file:2'));
    await waitForSessionCondition(() => runtime.loadedPlans.length == 2);
    expect(first.ownsLoadedContent('file:1'), isFalse);
    expect(first.ownsLoadedContent('file:2'), isFalse);
    pending.complete();
    expect((await replacing).outcome, LoadOutcome.failed);
    expect(first.ownsLoadedContent('file:1'), isFalse);

    final second = session.attach();
    runtime.onLoad = null;
    await second.load(sessionPlan('file:1'));
    expect(second.ownsLoadedContent('file:1'), isTrue);
    expect(first.ownsLoadedContent('file:1'), isFalse);
  });

  test('seek 等待原生资格时暂停可执行，较新目标替换旧等待', () async {
    final runtime = GatedSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('gate'), start: PlaybackStartPolicy.play);
    final first = owner.seek(const Duration(seconds: 2));
    expect((await owner.setPlaying(false)).outcome, CommandOutcome.applied);
    final second = owner.seek(const Duration(seconds: 3));
    expect((await first).outcome, CommandOutcome.superseded);
    expect(runtime.seekCalls, isEmpty);
    runtime.unblock();
    expect((await second).outcome, CommandOutcome.applied);
    expect(runtime.seekCalls, [const Duration(seconds: 3)]);
    owner.close();
    await runtime.released;
  });

  test('seek 资格等待超时释放订阅，迟到完成仍可开启后续提交', () async {
    final runtime = GatedSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      commandBudget: const Duration(milliseconds: 30),
    );
    final owner = session.attach();
    await owner.load(sessionPlan('gate'), start: PlaybackStartPolicy.play);
    final result = await owner.seek(const Duration(seconds: 2));
    expect(result.outcome, CommandOutcome.failed);
    expect(result.failure?.category, PlaybackFailureCategory.timeout);
    expect(runtime.changes.hasListener, isFalse);
    expect(runtime.seekCalls, isEmpty);
    runtime.unblock();
    expect(
      (await owner.seek(const Duration(seconds: 3))).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.changes.hasListener, isFalse);
    owner.close();
    await runtime.released;
  });

  test('关闭使外部 seek 等待立即结束，无需原生落点完成', () async {
    final runtime = GatedSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('gate'), start: PlaybackStartPolicy.play);
    final seek = owner.seek(const Duration(seconds: 2));
    owner.close();
    expect((await seek).outcome, CommandOutcome.superseded);
    await runtime.released;
    expect(runtime.seekCalls, isEmpty);
  });

  test('加载期间进入后台抑制后续播放，切换 owner 后仍保持策略', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final policy = PlaybackBackgroundPolicy(
      session: session,
      continuePlaying: false,
    );
    addTearDown(() {
      policy.dispose();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final first = session.attach();
    final pending = Completer<PlaybackPlan?>();
    final result = first.query(
      (_) => pending.future,
      start: PlaybackStartPolicy.play,
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(sessionPlan('first'));
    expect((await result).outcome, LoadOutcome.ready);
    expect(runtime.playCalls, [false]);
    final second = session.attach();
    await second.load(sessionPlan('second'), start: PlaybackStartPolicy.play);
    expect(runtime.playCalls.last, isFalse);
    expect(session.currentSnapshot.inhibitors, hasLength(1));
    policy.continuePlaying = true;
    await waitForSessionCondition(() => runtime.playCalls.last);
    expect(runtime.playCalls.last, isTrue);
    expect(session.currentSnapshot.inhibitors, isEmpty);
    policy.continuePlaying = false;
    await waitForSessionCondition(() => !runtime.playCalls.last);
    expect(runtime.playCalls.last, isFalse);
    await second.setPlaying(false);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.playCalls.last, isFalse);
    expect(session.currentSnapshot.inhibitors, isEmpty);
    first.close();
    second.close();
    await runtime.released;
  });

  test('直播候选确认无视频轨后立即尝试下一源，保留请求和播放意图', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    runtime.onLoad = (plan, context, index) async =>
        index == 0 ? audioSessionLoad(context) : preparedSessionLoad(context, plan);
    final result = await owner.load(
      sessionPlan(
        'live',
        kind: PlaybackTimelineKind.live,
        candidates: [
          'https://example.test/audio.flv',
          'https://example.test/video.flv',
        ],
      ),
      start: PlaybackStartPolicy.play,
    );
    expect(result.outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans.map((p) => p.source.videoIndex), [0, 1]);
    expect(runtime.playCalls, [true]);
    expect(session.currentSnapshot.requestId, 1);
    expect(session.currentSnapshot.loadId, 2);
    expect(session.currentPlan?.source.videoIndex, 1);
    owner.close();
    await runtime.released;
  });

  test('直播全部候选无视频轨时失败并停止重试', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    runtime.onLoad = (plan, context, index) async => audioSessionLoad(context);
    final result = await owner.load(
      sessionPlan(
        'live',
        kind: PlaybackTimelineKind.live,
        candidates: [
          'https://example.test/one.flv',
          'https://example.test/two.flv',
        ],
      ),
    );
    expect(result.outcome, LoadOutcome.failed);
    expect(result.failure?.operation, 'validate-live-video');
    expect(runtime.loadedPlans, hasLength(2));
    expect(runtime.playCalls, isEmpty);
    owner.close();
    await runtime.released;
  });

  test('直播轮换候选期间的暂停与新媒体请求仍优先生效', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final secondStarted = Completer<void>();
    final secondFinished = Completer<void>();
    runtime.onLoad = (plan, context, index) async {
      if (index == 0) return audioSessionLoad(context);
      if (index == 1) {
        secondStarted.complete();
        await secondFinished.future;
      }
      return preparedSessionLoad(context, plan);
    };
    final live = owner.load(
      sessionPlan(
        'live',
        kind: PlaybackTimelineKind.live,
        candidates: [
          'https://example.test/one.flv',
          'https://example.test/two.flv',
        ],
      ),
      start: PlaybackStartPolicy.play,
    );
    await secondStarted.future;
    await owner.setPlaying(false);
    final latest = owner.load(
      sessionPlan('latest'),
      start: PlaybackStartPolicy.preserve,
    );
    expect((await live).outcome, LoadOutcome.superseded);
    secondFinished.complete();
    expect((await latest).outcome, LoadOutcome.ready);
    expect(session.currentPlan?.contentKey, 'latest');
    expect(runtime.playCalls, [false]);
    owner.close();
    await runtime.released;
  });

  for (final live in [false, true]) {
    test('允许${live ? '显式纯音频直播' : '纯音频点播'}的无视频输出', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      runtime.onLoad = (plan, context, index) async => audioSessionLoad(context);
      final result = await owner.load(
        sessionPlan(
          'audio',
          kind: live
              ? PlaybackTimelineKind.live
              : PlaybackTimelineKind.onDemand,
          audioOnly: live,
        ),
      );
      expect(result.outcome, LoadOutcome.ready);
      expect(runtime.loadedPlans, hasLength(1));
      owner.close();
      await runtime.released;
    });
  }

  test('查询成功后业务回写仍属于当前媒体，下一次加载使其失效', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime, monotonicNow: () => now);
    final owner = session.attach();
    late PlaybackQuery query;
    final loaded = await owner.query((accepted) async {
      query = accepted;
      return sessionPlan('online-video');
    }, start: PlaybackStartPolicy.play);
    expect(loaded.outcome, LoadOutcome.ready);
    expect(query.isCurrent, isTrue, reason: '页面在 ready 后才挂载视频和字幕');
    now = const Duration(minutes: 1);
    expect(query.isCurrent, isTrue, reason: '成功加载后的回写不再受加载 deadline 限制');
    await owner.load(sessionPlan('next-video'));
    expect(query.isCurrent, isFalse);
    late PlaybackQuery current;
    await owner.query((accepted) async {
      current = accepted;
      return sessionPlan('next-video');
    });
    expect(current.isCurrent, isTrue);
    owner.invalidateRequests();
    expect(current.isCurrent, isFalse);
    owner.close();
    await session.shutdown();
  });

  test('新加载立即结算旧请求，但等旧原生调用排空后才执行新加载', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final oldOpen = Completer<void>();
    final oldStarted = Completer<void>();
    final calls = <String>[];
    runtime.onLoad = (plan, context, index) async {
      calls.add(plan.contentKey);
      if (index == 0) {
        oldStarted.complete();
        await oldOpen.future;
      }
      return preparedSessionLoad(context, plan);
    };

    final old = owner.load(sessionPlan('old'));
    await oldStarted.future;
    final latest = owner.load(sessionPlan('latest'));
    expect((await old).outcome, LoadOutcome.superseded);
    expect(calls, ['old']);

    oldOpen.complete();
    expect((await latest).outcome, LoadOutcome.ready);
    expect(calls, ['old', 'latest']);

    owner.close();
    final shutdown = await session.shutdown();
    expect(shutdown.outcome, PlaybackShutdownOutcome.released);
    expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
  });

  testWidgets('播放调用在原生写入未返回时也应按命令预算结束等待', (tester) async {
    var now = Duration.zero;
    const budget = Duration(milliseconds: 500);
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      commandBudget: budget,
      monotonicNow: () => now,
    );
    final owner = session.attach();
    final load = owner.load(sessionPlan('movie'));
    await tester.pump();
    expect((await load).outcome, LoadOutcome.ready);
    final nativeReply = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSetPlaying = (playing, context, _) {
      runtime.playCalls.add(playing);
      return nativeReply.future;
    };
    addTearDown(() async {
      if (!nativeReply.isCompleted) {
        nativeReply.complete(const PlaybackRuntimeCommandResult());
      }
      await tester.pump();
      owner.close();
      await tester.pump();
      await session.shutdown();
    });
    CommandResult? result;
    unawaited(owner.setPlaying(true).then((value) => result = value));
    await tester.pump();
    now = budget;
    await tester.pump(budget);
    expect(result, isNotNull, reason: 'commandBudget 到达后播放调用仍未结算');
    expect(result!.failure?.category, PlaybackFailureCategory.timeout);
    CommandResult? pauseResult;
    unawaited(owner.setPlaying(false).then((value) => pauseResult = value));
    await tester.pump();
    now += budget;
    await tester.pump(budget);
    expect(pauseResult?.failure?.category, PlaybackFailureCategory.timeout);
    expect(runtime.playCalls, [false, true]);
    nativeReply.complete(const PlaybackRuntimeCommandResult());
    await tester.pump();
    expect(runtime.playCalls, [false, true, false]);
    expect(result!.failure?.category, PlaybackFailureCategory.timeout);
    expect(session.currentSnapshot.intent.playing, isFalse);
  });

  test('旧 play 写入返回后 writer 收敛到更新的 pause 意图', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    expect((await owner.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);

    final oldPlay = Completer<PlaybackRuntimeCommandResult>();
    final playStarted = Completer<void>();
    runtime.onSetPlaying = (playing, context, index) {
      runtime.playCalls.add(playing);
      if (playing && index == 1) {
        playStarted.complete();
        return oldPlay.future;
      }
      return Future.value(const PlaybackRuntimeCommandResult());
    };

    final play = owner.setPlaying(true);
    await playStarted.future;
    final pause = owner.setPlaying(false);
    oldPlay.complete(const PlaybackRuntimeCommandResult());

    expect((await play).outcome, CommandOutcome.superseded);
    expect((await pause).outcome, CommandOutcome.applied);
    expect(runtime.playCalls, [false, true, false]);
    expect(session.currentSnapshot.intent.playing, isFalse);
    expect(session.currentSnapshot.actual.playing, isNull);

    owner.close();
    await runtime.released;
  });

  test('异步 query 被新请求取代后不能提交迟到计划', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final oldResolver = Completer<PlaybackPlan?>();
    final oldStarted = Completer<void>();
    runtime.onLoad = (plan, context, _) async => preparedSessionLoad(context, plan);

    final old = owner.query((query) {
      oldStarted.complete();
      return oldResolver.future;
    });
    await oldStarted.future;
    final latest = owner.load(sessionPlan('latest'));
    expect((await old).outcome, LoadOutcome.superseded);
    oldResolver.complete(sessionPlan('late'));

    expect((await latest).outcome, LoadOutcome.ready);
    expect(runtime.loadedKeys, ['latest']);
    owner.close();
    await runtime.released;
  });

  test('owner返回后须提交自己的load才恢复旧播放意图', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final previous = session.attach();
    expect((await previous.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);
    await previous.setPlaying(true);
    final routeToken = previous.acquireInhibitor(
      PlaybackInhibitorSource.system,
    );
    expect(routeToken, isNotNull);
    await waitForSessionCondition(() => !runtime.playCalls.last);

    final next = session.attach();
    expect((await next.load(sessionPlan('next'))).outcome, LoadOutcome.ready);
    await next.setPlaying(true);
    await waitForSessionCondition(() => runtime.playCalls.last);

    next.close();
    await waitForSessionCondition(() => !runtime.playCalls.last);
    expect(previous.isActive, isFalse);

    previous.activate();
    expect(previous.isActive, isTrue);
    await waitForSessionCondition(() => !runtime.playCalls.last);
    expect(
      (await previous.releaseInhibitor(routeToken!)).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.playCalls.last, isFalse);
    expect((await previous.setPlaying(true)).outcome, CommandOutcome.noMedia);
    expect((await previous.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);
    await waitForSessionCondition(() => runtime.playCalls.last);

    previous.close();
    await runtime.released;
  });

  test('网络点播提前 EOF 保留意图和位置并受三次恢复预算约束', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 2);
    final session = PlaybackSession(runtime: runtime, monotonicNow: () => now);
    final owner = session.attach();
    try {
      await owner.load(sessionPlan('truncated'), start: PlaybackStartPolicy.play);
      for (var i = 0; i < 3; i++) {
        now = Duration(seconds: [0, 10, 25][i]);
        runtime.eventController.add(
          PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: session.loadId,
          ),
        );
        await waitForSessionCondition(
          () =>
              runtime.loadedKeys.length == i + 2 &&
              session.currentSnapshot.phase == PlaybackPhase.ready,
        );
        expect(session.currentSnapshot.intent.playing, isTrue);
        expect(session.currentSnapshot.pendingAction, isNull);
        expect(
          runtime.loadedPlans.last.reloadPosition,
          const Duration(seconds: 2),
        );
      }
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      await waitForSessionCondition(() => session.currentSnapshot.phase == PlaybackPhase.failed);
      expect(runtime.loadedKeys, hasLength(4));
      expect(session.currentSnapshot.failure?.operation, 'automatic-recovery');
    } finally {
      owner.close();
      await session.shutdown();
    }
  });

  test('暂停时提前 EOF 保留停止意图，恢复播放后继续处理故障', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 2);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    try {
      await owner.load(sessionPlan('truncated'), start: PlaybackStartPolicy.pause);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.loadedKeys, hasLength(1));
      expect(session.currentSnapshot.intent.playing, isFalse);
      expect(session.currentSnapshot.pendingAction, isNull);
      await owner.setPlaying(true);
      runtime.emitActual(
        session.loadId,
        const PlaybackActual(
          playing: true,
          position: Duration(seconds: 2),
        ),
      );
      await waitForSessionCondition(() => runtime.loadedKeys.length == 2);
      expect(
        runtime.loadedPlans.last.reloadPosition,
        const Duration(seconds: 2),
      );
    } finally {
      owner.close();
      await session.shutdown();
    }
  });

  for (final position in [
    const Duration(seconds: 8),
    const Duration(seconds: 10),
  ]) {
    test('距正常片尾不超过两秒的 EOF 完成播放：$position', () async {
      final runtime = FakeSessionRuntime()..position = position;
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      try {
        await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
        runtime.eventController.add(
          PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: session.loadId,
          ),
        );
        expect(session.currentSnapshot.phase, PlaybackPhase.ended);
        expect(session.currentSnapshot.intent.playing, isFalse);
        expect(runtime.loadedKeys, hasLength(1));
      } finally {
        owner.close();
        await session.shutdown();
      }
    });
  }

  test('片尾 seek 重载目标位置并保留暂停意图和最新配置', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    try {
      await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
      final oldLoad = session.loadId;
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: oldLoad,
        ),
      );
      final action = session.currentSnapshot.pendingAction!;
      await owner.setVolume(37);
      expect(
        (await owner.seek(const Duration(seconds: 4))).outcome,
        CommandOutcome.applied,
      );
      expect(
        runtime.loadedPlans.last.startPosition,
        const Duration(seconds: 4),
      );
      expect(
        runtime.loadedPlans.last.reloadPosition,
        const Duration(seconds: 4),
      );
      expect(runtime.loadedPlans.last.configuration.volume, 37);
      expect(runtime.seekCalls, isEmpty);
      expect(runtime.playCalls.last, isFalse);
      expect(session.currentSnapshot.phase, PlaybackPhase.ready);
      expect(session.currentSnapshot.pendingAction, isNull);
      expect(
        (await owner.acknowledgeAction(action)).outcome,
        CommandOutcome.superseded,
      );
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: oldLoad,
        ),
      );
      expect(session.currentSnapshot.phase, PlaybackPhase.ready);
      runtime.position = const Duration(seconds: 10);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      expect(session.currentSnapshot.phase, PlaybackPhase.ended);
      expect(session.currentSnapshot.pendingAction!.id, isNot(action.id));
    } finally {
      owner.close();
      await session.shutdown();
    }
  });

  test('显式 seek 到片尾保留用户目标，包括播放结束后重载', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(session.shutdown);
    await owner.load(sessionPlan('tail'));
    expect(
      (await owner.seek(const Duration(seconds: 10))).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.seekCalls.last, const Duration(seconds: 10));
    runtime.eventController.add(
      PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: session.loadId,
      ),
    );
    expect(
      (await owner.seek(const Duration(seconds: 10))).outcome,
      CommandOutcome.applied,
    );
    expect(
      runtime.loadedPlans.last.reloadPosition,
      const Duration(seconds: 10),
    );
  });

  for (final playing in [false, true]) {
    test('片尾复播从零重载，在途最新播放意图生效：$playing', () async {
      final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      final opened = Completer<void>();
      try {
        await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
        runtime.eventController.add(
          PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: session.loadId,
          ),
        );
        runtime.onLoad = (plan, context, index) async {
          await opened.future;
          return preparedSessionLoad(context, plan);
        };
        final replay = owner.setPlaying(true);
        await waitForSessionCondition(() => runtime.loadedPlans.length == 2);
        await owner.setPlaying(false);
        if (playing) await owner.setPlaying(true);
        opened.complete();
        expect((await replay).outcome, CommandOutcome.applied);
        expect(runtime.loadedPlans.last.reloadPosition, Duration.zero);
        expect(runtime.playCalls.last, playing);
        expect(session.currentSnapshot.intent.playing, playing);
      } finally {
        if (!opened.isCompleted) opened.complete();
        owner.close();
        await session.shutdown();
      }
    });
  }

  test('片尾复播协调播放时暂停，等待 writer 落实较新意图', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final playing = Completer<void>();
    final finishPlay = Completer<void>();
    try {
      await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      runtime.onSetPlaying = (value, context, index) async {
        if (value) {
          playing.complete();
          await finishPlay.future;
        }
        runtime.playCalls.add(value);
        return const PlaybackRuntimeCommandResult();
      };
      final replay = owner.setPlaying(true);
      await playing.future;
      await owner.setPlaying(false);
      finishPlay.complete();
      expect((await replay).outcome, CommandOutcome.applied);
      expect(session.currentSnapshot.phase, PlaybackPhase.ready);
      expect(session.currentSnapshot.intent.playing, isFalse);
      expect(runtime.playCalls.last, isFalse);
    } finally {
      if (!finishPlay.isCompleted) finishPlay.complete();
      owner.close();
      await session.shutdown();
    }
  });

  test('片尾连续 seek 取代在途重载，保留期间最新播放意图', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final opened = Completer<void>();
    try {
      await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      runtime.onLoad = (plan, context, index) async {
        if (index == 1) await opened.future;
        return preparedSessionLoad(context, plan);
      };
      final first = owner.seek(const Duration(seconds: 2));
      await waitForSessionCondition(() => runtime.loadedPlans.length == 2);
      await owner.setPlaying(true);
      final second = owner.seek(const Duration(seconds: 5));
      final latest = owner.seek(const Duration(seconds: 7));
      expect((await first).outcome, CommandOutcome.superseded);
      expect((await second).outcome, CommandOutcome.superseded);
      opened.complete();
      expect((await latest).outcome, CommandOutcome.applied);
      expect(runtime.loadedPlans, hasLength(3));
      expect(
        runtime.loadedPlans.last.reloadPosition,
        const Duration(seconds: 7),
      );
      expect(runtime.playCalls.last, isTrue);
      expect(session.currentSnapshot.intent.playing, isTrue);
    } finally {
      if (!opened.isCompleted) opened.complete();
      owner.close();
      await session.shutdown();
    }
  });

  test('片尾 seek 范围和能力校验不触发重载，复播失败如实返回', () async {
    final runtime = FakeSessionRuntime()..position = const Duration(seconds: 10);
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    try {
      await owner.load(sessionPlan('tail'), start: PlaybackStartPolicy.play);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      expect(
        (await owner.seek(const Duration(seconds: 11))).outcome,
        CommandOutcome.outOfRange,
      );
      for (final support in [
        PlaybackSeekSupport.unknown,
        PlaybackSeekSupport.unsupported,
      ]) {
        runtime.eventController.add(
          PlaybackRuntimeCapabilitiesChanged(
            runtimeId: runtime.runtimeId,
            loadId: session.loadId,
            capabilities: PlaybackCapabilities(seekSupport: support),
          ),
        );
        expect(
          (await owner.seek(Duration.zero)).outcome,
          support == PlaybackSeekSupport.unknown
              ? CommandOutcome.capabilityPending
              : CommandOutcome.unsupported,
        );
      }
      expect(runtime.loadedPlans, hasLength(1));
      runtime.onLoad = (plan, context, index) async => failedSessionLoad(context);
      expect((await owner.setPlaying(true)).outcome, CommandOutcome.failed);
      expect(session.currentSnapshot.phase, PlaybackPhase.failed);
    } finally {
      owner.close();
      await session.shutdown();
    }
  });

  test('seek 命令回执在途时提前 EOF 不抢占，结束后按新位置恢复', () async {
    final pending = Completer<PlaybackRuntimeCommandResult>();
    final runtime = FakeSessionRuntime()
      ..position = const Duration(seconds: 2)
      ..onSeek = (_, _) => pending.future;
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    try {
      await owner.load(sessionPlan('seek-eof'), start: PlaybackStartPolicy.play);
      final seeking = owner.seek(const Duration(seconds: 4));
      await waitForSessionCondition(() => runtime.seekCalls.isNotEmpty);
      runtime
        ..emitActual(session.loadId, const PlaybackActual(playing: false))
        ..position = const Duration(seconds: 2);
      runtime.eventController.add(
        PlaybackRuntimeEnded(
          runtimeId: runtime.runtimeId,
          loadId: session.loadId,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.loadedKeys, hasLength(1));
      runtime.position = const Duration(seconds: 4);
      pending.complete(const PlaybackRuntimeCommandResult());
      expect((await seeking).outcome, CommandOutcome.applied);
      await waitForSessionCondition(() => runtime.loadedKeys.length == 2);
      expect(
        runtime.loadedPlans.last.reloadPosition,
        const Duration(seconds: 4),
      );
    } finally {
      if (!pending.isCompleted) {
        pending.complete(const PlaybackRuntimeCommandResult());
      }
      owner.close();
      await session.shutdown();
    }
  });

  for (final ended in [false, true]) {
    test('A${ended ? '播完' : '暂停'}后经过B/C/D返回仍保持停止，显式播放可恢复', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final a = session.attach();
      await a.load(sessionPlan('A'), start: PlaybackStartPolicy.play);
      if (ended) {
        runtime.eventController.add(
          PlaybackRuntimeEnded(
            runtimeId: runtime.runtimeId,
            loadId: session.loadId,
          ),
        );
        expect(session.currentSnapshot.phase, PlaybackPhase.ended);
      } else {
        await a.setPlaying(false);
      }
      final token = a.acquireInhibitor(PlaybackInhibitorSource.system)!;
      final pages = <PlaybackOwner>[];
      for (final key in ['B', 'C', 'D']) {
        final owner = session.attach();
        pages.add(owner);
        await owner.load(sessionPlan(key), start: PlaybackStartPolicy.play);
      }
      for (final owner in pages.reversed) {
        owner.close();
      }
      a.activate();
      await a.load(sessionPlan('A'));
      await a.releaseInhibitor(token);
      expect(session.currentSnapshot.intent.playing, isFalse);
      expect(runtime.playCalls.last, isFalse);
      await a.setPlaying(true);
      expect(runtime.playCalls.last, isTrue);
      a.close();
      await runtime.released;
    });
  }

  test('页面关闭但媒体租约尚未释放时，原生播放器立即暂停', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('movie'), start: PlaybackStartPolicy.play);
    final lease = owner.acquireKeepAlive()!;
    expect(runtime.playCalls.last, isTrue);

    owner.close();
    await waitForSessionCondition(() => !runtime.playCalls.last);
    expect(session.isDisposed, isFalse);

    lease.close();
    await runtime.released;
    expect(session.isDisposed, isTrue);
  });

  test('关闭inactive owner不影响当前活动owner的播放', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final previous = session.attach();
    expect((await previous.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);
    await previous.setPlaying(true);

    final active = session.attach();
    expect((await active.load(sessionPlan('next'))).outcome, LoadOutcome.ready);
    await active.setPlaying(true);
    await waitForSessionCondition(() => runtime.playCalls.last);

    previous.close();
    expect(active.isActive, isTrue);
    expect(session.currentSnapshot.intent.playing, isTrue);
    expect(runtime.playCalls.last, isTrue);

    active.close();
    await runtime.released;
  });

  test('session audio focus抑制跨owner load并按新owner最新意图恢复', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final previous = session.attach();
    expect((await previous.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);
    await previous.setPlaying(true);

    final focusToken = session.acquireSessionInhibitor(
      PlaybackInhibitorSource.audioFocus,
    );
    expect(focusToken, isNotNull);
    await waitForSessionCondition(() => !runtime.playCalls.last);

    final active = session.attach();
    expect(
      (await active.load(
        sessionPlan('next'),
        start: PlaybackStartPolicy.play,
      )).outcome,
      LoadOutcome.ready,
    );
    expect(active.isActive, isTrue);
    expect(session.currentSnapshot.intent.playing, isTrue);
    expect(runtime.playCalls.last, isFalse);

    expect((await active.setPlaying(false)).outcome, CommandOutcome.applied);
    expect(
      (await session.releaseSessionInhibitor(focusToken!)).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.playCalls.last, isFalse);

    expect((await active.setPlaying(true)).outcome, CommandOutcome.applied);
    await waitForSessionCondition(() => runtime.playCalls.last);

    active.close();
    previous.close();
    await runtime.released;
  });

  test('snapshot 新订阅即时给当前值，暂停期间只保留 latest', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final received = <PlaybackSnapshot>[];
    final firstSnapshot = Completer<void>();
    final subscription = owner.snapshots.listen((snapshot) {
      received.add(snapshot);
      if (!firstSnapshot.isCompleted) firstSnapshot.complete();
    });
    await firstSnapshot.future;
    expect(
      received.single.snapshotVersion,
      session.currentSnapshot.snapshotVersion,
    );

    subscription.pause();
    final tokens = <PlaybackInhibitorToken>[];
    for (var i = 0; i < 20; i++) {
      tokens.add(owner.acquireInhibitor(PlaybackInhibitorSource.system)!);
    }
    for (final token in tokens) {
      await owner.releaseInhibitor(token);
    }
    final versionBeforeResume = session.currentSnapshot.snapshotVersion;
    final countBeforeResume = received.length;
    subscription.resume();
    await waitForSessionCondition(() => received.length > countBeforeResume);
    expect(received.length, countBeforeResume + 1);
    expect(received.last.snapshotVersion, versionBeforeResume);

    await subscription.cancel();
    owner.close();
    await runtime.released;
  });

  test('seek 受 timeline 与已知区间约束', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    expect((await owner.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);

    expect(
      (await owner.seek(const Duration(seconds: -1))).outcome,
      CommandOutcome.outOfRange,
    );
    expect(
      (await owner.seek(const Duration(seconds: 11))).outcome,
      CommandOutcome.outOfRange,
    );
    expect(
      (await owner.seek(const Duration(seconds: 10))).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.seekCalls, [const Duration(seconds: 10)]);

    owner.close();
    await runtime.released;
  });

  test('不可 seek 直播的 shader 重建走同一加载协议并保留 request 与播放意图', () async {
    final runtime = FakeSessionRuntime()..shaderChangeRequiresRendererReset = true;
    final session = PlaybackSession(
      runtime: runtime,
      commandBudget: Duration.zero,
    );
    final owner = session.attach();
    expect(
      (await owner.load(
        sessionPlan(
          'live',
          kind: PlaybackTimelineKind.live,
          seekPolicy: PlaybackSeekPolicy.unknown,
        ),
        start: PlaybackStartPolicy.play,
      )).outcome,
      LoadOutcome.ready,
    );
    final requestId = session.requestId;
    final previousLoadId = session.loadId;

    expect(
      (await owner.setShader(['quality'])).outcome,
      CommandOutcome.applied,
    );
    expect(session.requestId, requestId);
    expect(session.loadId, previousLoadId + 1);
    expect(runtime.loadedPlans, hasLength(2));
    expect(runtime.loadedPlans.last.configuration.shaders, ['quality']);
    expect(runtime.loadedPlans.last.startPosition, isNull);
    expect(runtime.loadedPlans.last.reloadPosition, isNull);
    expect(runtime.shaderCalls, isEmpty);
    expect(session.currentSnapshot.intent.playing, isTrue);
    expect(runtime.playCalls, [true, false, true]);

    owner.close();
    await runtime.released;
  });

  for (final playing in [true, false]) {
    test('点播 shader 重建通过卸载重载恢复位置与播放意图 playing=$playing', () async {
      final runtime = FakeSessionRuntime()..shaderChangeRequiresRendererReset = true;
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      expect(
        (await owner.load(
          sessionPlan('movie'),
          start: playing ? PlaybackStartPolicy.play : PlaybackStartPolicy.pause,
        )).outcome,
        LoadOutcome.ready,
      );
      runtime.position = const Duration(milliseconds: 4321);
      final requestId = session.requestId;
      final loadId = session.loadId;
      expect(
        (await owner.setShader(['quality'])).outcome,
        CommandOutcome.applied,
      );
      expect(session.requestId, requestId);
      expect(session.loadId, loadId + 1);
      expect(runtime.shaderCalls, isEmpty);
      expect(
        runtime.loadedPlans.last.source,
        same(runtime.loadedPlans.first.source),
      );
      expect(runtime.loadedPlans.last.configuration.shaders, ['quality']);
      expect(
        runtime.loadedPlans.last.reloadPosition,
        const Duration(milliseconds: 4321),
      );
      expect(session.currentSnapshot.intent.playing, playing);
      expect(runtime.playCalls.last, playing);
      expect((await owner.setShader([])).outcome, CommandOutcome.applied);
      expect(session.loadId, loadId + 2);
      expect(runtime.loadedPlans.last.configuration.shaders, isEmpty);
      expect(session.currentSnapshot.intent.playing, playing);
      owner.close();
      await runtime.released;
    });
  }

  test('不可 seek 直播的解码器和音频模式改动经加载协议应用', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    expect(
      (await owner.load(
        sessionPlan(
          'live',
          kind: PlaybackTimelineKind.live,
          seekPolicy: PlaybackSeekPolicy.unknown,
        ),
      )).outcome,
      LoadOutcome.ready,
    );

    expect(
      (await owner.setDecoder(const PlaybackDecoder('no'))).outcome,
      CommandOutcome.applied,
    );
    expect((await owner.setAudioOnly(true)).outcome, CommandOutcome.applied);
    expect(
      (await owner.setPlaybackSpeed(
        1.5,
        mediaOptions: const {'cache-secs': '5'},
      )).outcome,
      CommandOutcome.applied,
    );

    expect(runtime.loadedPlans, hasLength(3));
    expect(runtime.loadedPlans[1].configuration.hwdec, 'no');
    expect(runtime.loadedPlans[1].configuration.audioOnly, isFalse);
    expect(runtime.loadedPlans[2].configuration.hwdec, 'no');
    expect(runtime.loadedPlans[2].configuration.audioOnly, isTrue);
    expect(runtime.decoderCalls, isEmpty);
    expect(runtime.audioOnlyCalls, isEmpty);

    owner.close();
    await runtime.released;
  });

  test('无需重建输出的点播 shader、解码器和音频模式原位更新', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    expect((await owner.load(sessionPlan('movie'))).outcome, LoadOutcome.ready);

    expect(
      (await owner.setShader(['quality'])).outcome,
      CommandOutcome.applied,
    );
    expect(
      (await owner.setDecoder(const PlaybackDecoder('no'))).outcome,
      CommandOutcome.applied,
    );
    expect((await owner.setAudioOnly(true)).outcome, CommandOutcome.applied);

    expect(runtime.loadedPlans, hasLength(1));
    expect(runtime.shaderCalls, [
      ['quality'],
    ]);
    expect(runtime.decoderCalls, ['no']);
    expect(runtime.audioOnlyCalls, [true]);
    expect(
      (await owner.setPlaybackSpeed(
        1.5,
        mediaOptions: const {'cache-secs': '5'},
      )).outcome,
      CommandOutcome.applied,
    );
    expect(runtime.speedCalls.single.speed, 1.5);
    expect(runtime.speedCalls.single.mediaOptions, {'cache-secs': '5'});
    expect(session.currentSnapshot.configuration.applied.shaders, ['quality']);
    expect(
      session.currentSnapshot.configuration.applied.mediaOptions,
      {'cache-secs': '5'},
    );

    owner.close();
    await runtime.released;
  });

  test('activate 交接后旧媒体结束与失败不归属未加载页面', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final first = session.attach();
    await first.load(sessionPlan('movie'));
    final oldLoad = session.loadId;
    final second = session.attach();
    first.activate();
    runtime.eventController.add(
      PlaybackRuntimeEnded(
        runtimeId: runtime.runtimeId,
        loadId: oldLoad,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
    );
    runtime.eventController.add(
      const PlaybackRuntimeFailure(
        runtimeId: 51,
        loadId: 1,
        failure: PlaybackFailure(
          category: PlaybackFailureCategory.source,
          operation: 'old',
          stage: PlaybackStage.observing,
          recoverable: false,
          cause: 'old failure',
        ),
      ),
    );
    expect(session.currentSnapshot.pendingAction, isNull);
    expect(session.currentSnapshot.phase, PlaybackPhase.ready);
    expect(session.currentSnapshot.failure, isNull);
    first.close();
    second.close();
    await session.shutdown();
  });

  test('查询新来源时旧媒体失败不污染新请求', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('first'));
    final oldLoad = session.loadId;
    final resolve = Completer<PlaybackPlan?>();
    final loading = owner.query((_) => resolve.future);
    runtime.eventController.add(
      PlaybackRuntimeFailure(
        runtimeId: runtime.runtimeId,
        loadId: oldLoad,
        failure: const PlaybackFailure(
          category: PlaybackFailureCategory.source,
          operation: 'old',
          stage: PlaybackStage.observing,
          recoverable: false,
          cause: 'old failure',
        ),
      ),
    );
    expect(session.currentSnapshot.phase, PlaybackPhase.loading);
    expect(session.currentSnapshot.failure, isNull);
    resolve.complete(sessionPlan('second'));
    expect((await loading).outcome, LoadOutcome.ready);
    owner.close();
    await session.shutdown();
  });

  test('当前加载的原生失败仍发布到快照', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final started = Completer<PlaybackExecutionContext>();
    final finish = Completer<void>();
    runtime.onLoad = (plan, context, _) async {
      started.complete(context);
      await finish.future;
      return failedSessionLoad(context);
    };
    final loading = owner.load(sessionPlan('movie'));
    final context = await started.future;
    const failure = PlaybackFailure(
      category: PlaybackFailureCategory.source,
      operation: 'current',
      stage: PlaybackStage.opening,
      recoverable: false,
      cause: 'current failure',
    );
    runtime.eventController.add(
      PlaybackRuntimeFailure(
        runtimeId: runtime.runtimeId,
        loadId: context.loadId,
        failure: failure,
      ),
    );
    expect(session.currentSnapshot.phase, PlaybackPhase.failed);
    expect(session.currentSnapshot.failure, same(failure));
    finish.complete();
    expect((await loading).outcome, LoadOutcome.failed);
    owner.close();
    await session.shutdown();
  });

  test('旧 writer 异常不污染新媒体加载', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final first = session.attach();
    await first.load(sessionPlan('first'));
    final started = Completer<void>();
    final release = Completer<void>();
    runtime.onSetPlaying = (value, _, _) async {
      if (value) {
        started.complete();
        await release.future;
        throw StateError('old write failed');
      }
      return const PlaybackRuntimeCommandResult();
    };
    final old = first.setPlaying(true);
    await started.future;
    final second = session.attach();
    final loading = second.load(sessionPlan('second'));
    expect((await old).outcome, CommandOutcome.superseded);
    release.complete();
    expect((await loading).outcome, LoadOutcome.ready);
    expect(session.currentSnapshot.failure, isNull);
    first.close();
    second.close();
    await session.shutdown();
  });

  test('当前播放意图的原生异常返回失败', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('movie'));
    runtime.onSetPlaying = (value, _, _) async {
      if (value) throw StateError('current write failed');
      return const PlaybackRuntimeCommandResult();
    };
    final result = await owner.setPlaying(true);
    expect(result.outcome, CommandOutcome.failed);
    expect(result.failure!.cause, contains('current write failed'));
    owner.close();
    await session.shutdown();
  });

  test('空查询结果的失败原因与快照一致', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final result = await owner.query((_) async => null);
    expect(result.outcome, LoadOutcome.failed);
    expect(session.currentSnapshot.phase, PlaybackPhase.failed);
    expect(session.currentSnapshot.failure, same(result.failure));
    owner.close();
    await session.shutdown();
  });

  for (final unsupported in [false, true]) {
    test('配置${unsupported ? '不支持' : '失败'}后同值可重试', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      await owner.load(sessionPlan('movie'));
      const failure = PlaybackFailure(
        category: PlaybackFailureCategory.source,
        operation: 'muted',
        stage: PlaybackStage.observing,
        recoverable: true,
        cause: 'test failure',
      );
      runtime.onSetMuted = (_, _) async => unsupported
          ? const PlaybackRuntimeCommandResult(applied: false)
          : const PlaybackRuntimeCommandResult(
              applied: false,
              failure: failure,
            );
      for (var i = 0; i < 2; i++) {
        final result = await owner.setMuted(true);
        expect(
          result.outcome,
          unsupported ? CommandOutcome.unsupported : CommandOutcome.failed,
        );
        expect(session.currentSnapshot.configuration.pending, isEmpty);
        expect(session.currentSnapshot.configuration.desired.muted, isTrue);
        expect(session.currentSnapshot.configuration.applied.muted, isFalse);
      }
      runtime.onSetMuted = null;
      expect((await owner.setMuted(true)).outcome, CommandOutcome.applied);
      expect(runtime.mutedCalls, [true, true, true]);
      expect(session.currentSnapshot.configuration.applied.muted, isTrue);
      owner.close();
      await session.shutdown();
    });
  }

  test('在途配置的同值请求保持 accepted，完成后为 applied', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('movie'));
    final pending = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSetMuted = (_, _) => pending.future;
    final first = owner.setMuted(true);
    await waitForSessionCondition(() => runtime.mutedCalls.isNotEmpty);
    expect((await owner.setMuted(true)).outcome, CommandOutcome.accepted);
    expect(runtime.mutedCalls, [true]);
    pending.complete(const PlaybackRuntimeCommandResult());
    expect((await first).outcome, CommandOutcome.applied);
    expect((await owner.setMuted(true)).outcome, CommandOutcome.applied);
    owner.close();
    await session.shutdown();
  });

  test('旧配置失败不能清除新修订的 pending', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('movie'));
    final first = Completer<PlaybackRuntimeCommandResult>();
    final second = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSetMuted = (value, _) => value ? first.future : second.future;
    final old = owner.setMuted(true);
    await waitForSessionCondition(() => runtime.mutedCalls.length == 1);
    final next = owner.setMuted(false);
    first.complete(const PlaybackRuntimeCommandResult(applied: false));
    await old;
    await waitForSessionCondition(() => runtime.mutedCalls.length == 2);
    expect(
      session.currentSnapshot.configuration.pending,
      contains(PlaybackConfigurationKey.muted),
    );
    second.complete(const PlaybackRuntimeCommandResult());
    expect((await next).outcome, CommandOutcome.applied);
    expect(session.currentSnapshot.configuration.pending, isEmpty);
    owner.close();
    await session.shutdown();
  });

  test('静音与音量独立，新媒体恢复默认非静音', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('first'));
    expect((await owner.setMuted(true)).outcome, CommandOutcome.applied);
    expect((await owner.setVolume(37)).outcome, CommandOutcome.applied);
    expect(session.currentSnapshot.configuration.applied.muted, isTrue);
    expect(session.currentSnapshot.configuration.applied.volume, 37);
    expect((await owner.setMuted(false)).outcome, CommandOutcome.applied);
    expect(runtime.mutedCalls, [true, false]);
    expect(runtime.volumeCalls, [37]);
    expect(session.currentSnapshot.configuration.applied.volume, 37);
    await owner.setMuted(true);
    await owner.load(sessionPlan('second'));
    expect(runtime.loadedPlans.last.configuration.muted, isFalse);
    expect(session.currentSnapshot.configuration.applied.muted, isFalse);
    owner.close();
    await session.shutdown();
  });

  test('加载期间的静音变更合并入最终计划', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final started = Completer<void>();
    final finish = Completer<void>();
    runtime.onLoad = (plan, context, index) async {
      if (index == 0) {
        started.complete();
        await finish.future;
      }
      return preparedSessionLoad(context, plan);
    };
    final loading = owner.load(sessionPlan('first'));
    await started.future;
    expect((await owner.setMuted(true)).outcome, CommandOutcome.accepted);
    expect((await owner.setMuted(true)).outcome, CommandOutcome.accepted);
    finish.complete();
    expect((await loading).outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans.last.configuration.muted, isTrue);
    expect(session.currentSnapshot.configuration.applied.muted, isTrue);
    owner.close();
    await session.shutdown();
  });

  test('迟到静音命令与旧 owner 不能覆盖新媒体状态', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('first'));
    final pending = Completer<PlaybackRuntimeCommandResult>();
    late PlaybackExecutionContext context;
    runtime.onSetMuted = (_, c) {
      context = c;
      return pending.future;
    };
    final oldCommand = owner.setMuted(true);
    await waitForSessionCondition(() => runtime.mutedCalls.isNotEmpty);
    final newOwner = session.attach();
    final next = newOwner.load(sessionPlan('second'));
    expect(context.isCurrent(), isFalse);
    pending.complete(const PlaybackRuntimeCommandResult());
    await oldCommand;
    expect((await next).outcome, LoadOutcome.ready);
    expect(session.currentSnapshot.configuration.applied.muted, isFalse);
    expect((await owner.setMuted(true)).outcome, CommandOutcome.inactive);
    expect(runtime.loadedPlans.last.configuration.muted, isFalse);
    owner.close();
    newOwner.close();
    await session.shutdown();
  });

  test('音轨重连经过会话命令，保留视频代次、暂停意图和音量', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('movie'), start: PlaybackStartPolicy.pause);
    await owner.setVolume(37);
    final snapshot = session.currentSnapshot;
    expect((await owner.reloadAudio()).outcome, CommandOutcome.applied);
    expect(runtime.audioReloadContexts, hasLength(1));
    expect(runtime.audioReloadContexts.single.loadId, snapshot.loadId);
    expect(runtime.loadedPlans, hasLength(1));
    expect(session.currentSnapshot.loadId, snapshot.loadId);
    expect(session.currentSnapshot.intent.playing, isFalse);
    expect(session.currentSnapshot.configuration.desired.volume, 37);
    expect(runtime.seekCalls, isEmpty);
    owner.close();
    await session.shutdown();
  });

  test('手动播放前仅解析来源正常结束，保留查询身份且不标记失败', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    late PlaybackQuery query;
    final result = await owner.query(
      (value) async {
        query = value;
        return sessionPlan('manual');
      },
      start: PlaybackStartPolicy.pause,
      shouldLoad: () => false,
    );
    expect(result.outcome, LoadOutcome.noMedia);
    expect(session.currentSnapshot.phase, PlaybackPhase.idle);
    expect(session.currentSnapshot.failure, isNull);
    expect(runtime.loadedPlans, isEmpty);
    expect(query.isCurrent, isTrue);
    await owner.load(sessionPlan('manual'), start: PlaybackStartPolicy.play);
    expect(query.isCurrent, isFalse);
    expect(runtime.loadedKeys, ['manual']);
    owner.close();
    await session.shutdown();
  });

  test('来源查询未返回时点击播放，查询完成后加载并落实最新意图', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final source = Completer<PlaybackPlan>();
    var load = false;
    final query = owner.query(
      (_) => source.future,
      start: PlaybackStartPolicy.pause,
      shouldLoad: () => load,
    );
    load = true;
    await owner.setPlaying(true);
    source.complete(sessionPlan('manual'));
    expect((await query).outcome, LoadOutcome.ready);
    expect(runtime.loadedKeys, ['manual']);
    expect(runtime.playCalls.last, isTrue);
    owner.close();
    await session.shutdown();
  });

  test('音轨重连中切源使旧结果失效，原生命令排空后再加载新媒体', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final pending = Completer<PlaybackRuntimeCommandResult>();
    runtime.onReloadAudio = (_) => pending.future;
    addTearDown(() async {
      if (!pending.isCompleted) {
        pending.complete(const PlaybackRuntimeCommandResult());
      }
      owner.close();
      await session.shutdown();
    });
    await owner.load(sessionPlan('first'));
    final repair = owner.reloadAudio();
    await waitForSessionCondition(() => runtime.audioReloadContexts.isNotEmpty);
    final nextLoad = owner.load(sessionPlan('second'));
    expect((await repair).outcome, CommandOutcome.superseded);
    expect(runtime.audioReloadContexts.single.isCurrent(), isFalse);
    expect(runtime.loadedKeys, ['first']);
    pending.complete(const PlaybackRuntimeCommandResult());
    expect((await nextLoad).outcome, LoadOutcome.ready);
    expect(runtime.loadedKeys, ['first', 'second']);
    expect(session.currentPlan?.contentKey, 'second');
  });

  test('地址重新解析时暂停旧媒体，失败后保持静音与用户意图', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(() async {
      owner.close();
      await runtime.released;
    });
    await owner.load(sessionPlan('movie'), start: PlaybackStartPolicy.play);
    final resolving = Completer<PlaybackPlan?>();
    final query = owner.query((_) => resolving.future);
    await waitForSessionCondition(() => !runtime.playCalls.last);
    expect(session.currentSnapshot.phase, PlaybackPhase.loading);
    expect(session.currentSnapshot.intent.playing, isTrue);
    resolving.complete(null);
    expect((await query).outcome, LoadOutcome.failed);
    expect(runtime.playCalls.last, isFalse);
    expect(session.currentSnapshot.intent.playing, isTrue);
  });

  test('运行时失败使迟到的 play 收敛到暂停', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final playing = Completer<void>();
    final started = Completer<void>();
    addTearDown(() async {
      if (!playing.isCompleted) playing.complete();
      owner.close();
      await runtime.released;
    });
    await owner.load(sessionPlan('movie'));
    runtime.onSetPlaying = (value, context, index) async {
      if (value) {
        started.complete();
        await playing.future;
      }
      runtime.playCalls.add(value);
      return const PlaybackRuntimeCommandResult();
    };
    final command = owner.setPlaying(true);
    await started.future;
    runtime.eventController.add(
      PlaybackRuntimeFailure(
        runtimeId: runtime.runtimeId,
        loadId: session.loadId,
        failure: const PlaybackFailure(
          category: PlaybackFailureCategory.source,
          operation: 'read',
          stage: PlaybackStage.observing,
          recoverable: true,
          cause: 'source-failed',
        ),
      ),
    );
    playing.complete();
    await command;
    await waitForSessionCondition(() => runtime.playCalls.length >= 3);
    expect(runtime.playCalls.last, isFalse);
    expect(session.currentSnapshot.phase, PlaybackPhase.failed);
  });

  test('重新加载中用户暂停，输出就绪后保持暂停', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(() async {
      owner.close();
      await runtime.released;
    });
    await owner.load(sessionPlan('movie'), start: PlaybackStartPolicy.play);
    final resolving = Completer<PlaybackPlan?>();
    final query = owner.query((_) => resolving.future);
    await waitForSessionCondition(() => !runtime.playCalls.last);
    await owner.setPlaying(false);
    resolving.complete(sessionPlan('movie'));
    expect((await query).outcome, LoadOutcome.ready);
    expect(runtime.playCalls.last, isFalse);
    expect(session.currentSnapshot.intent.playing, isFalse);
  });

  test('同页切来源及地址查询完成后从最新位置续播', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final plan = sessionPlan('movie', duration: const Duration(seconds: 1200));
    await owner.load(plan, start: PlaybackStartPolicy.play);
    runtime.position = const Duration(milliseconds: 123456);
    await owner.load(plan.withSource(sessionPlan('cdn').source));
    expect(runtime.loadedPlans.last.startPosition, runtime.position);

    final resolving = Completer<PlaybackPlan?>();
    final query = owner.query((_) => resolving.future);
    runtime.position = const Duration(milliseconds: 125678);
    resolving.complete(plan);
    await query;
    expect(runtime.loadedPlans.last.startPosition, runtime.position);
    owner.close();
    await runtime.released;
  });

  for (final queryFirst in [false, true]) {
    test('历史起点超出时长时${queryFirst ? '来源查询' : '直接加载'}从片头播放，重试不重复越界', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      addTearDown(session.shutdown);
      final base = sessionPlan('expired-history');
      final plan = PlaybackPlan(
        contentKey: base.contentKey,
        source: base.source,
        timeline: base.timeline,
        configuration: base.configuration,
        startPosition: const Duration(seconds: 20),
        reloadPosition: const Duration(seconds: 20),
      );
      runtime.onLoad = (plan, context, _) async {
        final start = plan.reloadPosition ?? plan.startPosition;
        // 回放原生从结束位置打开后立即 EOF、无法确认加载成功的行为。
        return start != null && start >= plan.timeline.duration!
            ? failedSessionLoad(context)
            : preparedSessionLoad(context, plan);
      };

      final result = queryFirst
          ? await owner.query((_) async => plan)
          : await owner.load(plan);
      expect(result.outcome, LoadOutcome.ready);
      expect(runtime.loadedPlans.single.startPosition, Duration.zero);
      expect(runtime.loadedPlans.single.reloadPosition, Duration.zero);

      // 原生末帧的轻微越界也不能被下次重载永久带回。
      runtime.position = const Duration(milliseconds: 10020);
      for (var i = 0; i < 2; i++) {
        expect((await owner.retry()).outcome, LoadOutcome.ready);
        expect(runtime.loadedPlans.last.reloadPosition, Duration.zero);
      }
    });
  }

  for (final example in [
    (
      name: '等于时长',
      start: const Duration(seconds: 10),
      duration: const Duration(seconds: 10),
      expected: Duration.zero,
      live: false,
    ),
    (
      name: '负数',
      start: const Duration(seconds: -1),
      duration: const Duration(seconds: 10),
      expected: Duration.zero,
      live: false,
    ),
    (
      name: '未知时长',
      start: const Duration(seconds: 20),
      duration: null,
      expected: const Duration(seconds: 20),
      live: false,
    ),
    (
      name: '零时长',
      start: const Duration(seconds: 20),
      duration: Duration.zero,
      expected: const Duration(seconds: 20),
      live: false,
    ),
    (
      name: '有效位置',
      start: const Duration(seconds: 9),
      duration: const Duration(seconds: 10),
      expected: const Duration(seconds: 9),
      live: false,
    ),
    (
      name: '直播',
      start: const Duration(seconds: 9),
      duration: null,
      expected: null,
      live: true,
    ),
  ]) {
    test('历史起点边界：${example.name}', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      addTearDown(session.shutdown);
      final base = sessionPlan(
        'boundary',
        kind: example.live
            ? PlaybackTimelineKind.live
            : PlaybackTimelineKind.onDemand,
      );
      final plan = PlaybackPlan(
        contentKey: base.contentKey,
        source: base.source,
        timeline: PlaybackTimeline(
          kind: base.timeline.kind,
          seekPolicy: base.timeline.seekPolicy,
          duration: example.duration,
        ),
        configuration: base.configuration,
        startPosition: example.start,
        reloadPosition: example.start,
      );
      expect((await owner.load(plan)).outcome, LoadOutcome.ready);
      expect(runtime.loadedPlans.single.startPosition, example.expected);
      expect(runtime.loadedPlans.single.reloadPosition, example.expected);
    });
  }

  for (final hint in [null, const Duration(seconds: 30)]) {
    test('首次加载确认实际时长越界后同一请求从零重试：$hint', () async {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      addTearDown(session.shutdown);
      final base = sessionPlan('short-runtime', duration: hint);
      final plan = PlaybackPlan(
        contentKey: base.contentKey,
        source: base.source,
        timeline: base.timeline,
        configuration: base.configuration,
        startPosition: const Duration(seconds: 20),
      );
      runtime.onLoad = (plan, context, index) async {
        if (index == 0) {
          runtime.emitActual(
            context.loadId,
            const PlaybackActual(
              duration: Duration(seconds: 10),
              position: Duration(seconds: 20),
            ),
          );
          return failedSessionLoad(context);
        }
        return preparedSessionLoad(context, plan);
      };
      expect(
        (await owner.load(plan, start: PlaybackStartPolicy.pause)).outcome,
        LoadOutcome.ready,
      );
      expect(runtime.loadedPlans, hasLength(2));
      expect(runtime.loadedPlans.last.startPosition, Duration.zero);
      expect(session.currentSnapshot.intent.playing, isFalse);
    });
  }

  test('成功打开但确认起点越界时仍从零重新打开一次', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(session.shutdown);
    final base = sessionPlan('loaded-overrun', duration: null);
    final plan = PlaybackPlan(
      contentKey: base.contentKey,
      source: base.source,
      timeline: base.timeline,
      configuration: base.configuration,
      startPosition: const Duration(seconds: 20),
    );
    runtime.onLoad = (plan, context, index) async {
      if (index == 0) {
        runtime.emitActual(
          context.loadId,
          const PlaybackActual(duration: Duration(seconds: 10)),
        );
      }
      return preparedSessionLoad(context, plan);
    };
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans, hasLength(2));
    expect(runtime.loadedPlans.last.startPosition, Duration.zero);
  });

  test('越界回退失败后不盲目重试，未证实越界也不重试', () async {
    for (final hasDuration in [false, true]) {
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(runtime: runtime);
      final owner = session.attach();
      final base = sessionPlan('bounded', duration: null);
      final plan = PlaybackPlan(
        contentKey: base.contentKey,
        source: base.source,
        timeline: base.timeline,
        configuration: base.configuration,
        startPosition: const Duration(seconds: 20),
      );
      runtime.onLoad = (plan, context, index) async {
        if (hasDuration) {
          runtime.emitActual(
            context.loadId,
            const PlaybackActual(duration: Duration(seconds: 10)),
          );
        }
        return failedSessionLoad(context);
      };
      expect((await owner.load(plan)).outcome, LoadOutcome.failed);
      expect(runtime.loadedPlans, hasLength(hasDuration ? 2 : 1));
      await session.shutdown();
    }
  });

  test('旧内容时长不修正新内容的起点', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(session.shutdown);
    await owner.load(sessionPlan('old'));
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(duration: Duration(seconds: 10)),
    );
    final next = sessionPlan('new', duration: null);
    final plan = PlaybackPlan(
      contentKey: next.contentKey,
      source: next.source,
      timeline: next.timeline,
      configuration: next.configuration,
      startPosition: const Duration(seconds: 20),
    );
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans.last.startPosition, const Duration(seconds: 20));
  });

  test('实际时长短于来源提示时，重载按实际时长修正', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    addTearDown(session.shutdown);
    final plan = sessionPlan('short-actual', duration: const Duration(seconds: 30));
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);
    runtime
      ..emitActual(
        session.loadId,
        const PlaybackActual(duration: Duration(seconds: 10)),
      )
      ..position = const Duration(seconds: 20);
    expect((await owner.retry()).outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans.last.reloadPosition, Duration.zero);
  });

  test('重载失败清零后连续重试保留续播位置，seek 后使用新的当前位置', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final plan = sessionPlan('movie', duration: const Duration(seconds: 1200));
    await owner.load(plan, start: PlaybackStartPolicy.play);
    runtime.position = const Duration(milliseconds: 123456);
    runtime.onLoad = (plan, context, index) async {
      runtime.position = Duration.zero;
      return failedSessionLoad(context);
    };
    await owner.retry();
    await owner.retry();
    expect(
      runtime.loadedPlans.last.startPosition,
      const Duration(milliseconds: 123456),
    );
    runtime.onLoad = null;
    await owner.retry();
    runtime.position = const Duration(seconds: 10);
    await owner.retry();
    expect(runtime.loadedPlans.last.startPosition, const Duration(seconds: 10));
    owner.close();
    await runtime.released;
  });

  test('新内容首次加载失败后可重试，使用失败内容的来源与起播位置', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('old'));
    runtime.position = const Duration(seconds: 99);
    runtime.onLoad = (plan, context, index) async {
      runtime.position = Duration.zero;
      return failedSessionLoad(context);
    };
    await owner.load(sessionPlan('new'));
    runtime.onLoad = null;
    expect((await owner.retry()).outcome, LoadOutcome.ready);
    expect(runtime.loadedPlans.last.contentKey, 'new');
    expect(runtime.loadedPlans.last.startPosition, isNull);
    owner.close();
    await runtime.released;
  });

  test('自动恢复从当前播放位置继续，保留当前配置和来源候选', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final plan = sessionPlan('movie', duration: const Duration(seconds: 1200));
    await owner.load(plan, start: PlaybackStartPolicy.play);
    await owner.setVolume(37);
    runtime
      ..emitActual(
        session.loadId,
        const PlaybackActual(
          playing: true,
          position: Duration(seconds: 1),
        ),
      )
      // 原生进度持续变化时不会为每一帧发布规范状态快照。
      ..position = const Duration(milliseconds: 867600);
    expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
    final reloaded = runtime.loadedPlans.last;
    expect(reloaded.startPosition, const Duration(milliseconds: 867600));
    expect(reloaded.reloadPosition, const Duration(milliseconds: 867600));
    expect(reloaded.configuration.volume, 37);
    expect(reloaded.source, same(plan.source));
    owner.close();
    await session.shutdown();
  });

  test('延期恢复在执行时捕获新位置，直播恢复不携带位置', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final plan = sessionPlan('movie');
    await owner.load(plan, start: PlaybackStartPolicy.play);
    await owner.setPlaying(false);
    expect((await owner.recover(plan)).outcome, LoadOutcome.deferred);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(
        playing: false,
        position: Duration(seconds: 8),
      ),
    );
    await owner.setPlaying(true);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(
        playing: true,
        videoProgressing: false,
        position: Duration(seconds: 8),
      ),
    );
    await waitForSessionCondition(() => runtime.loadedPlans.length == 2);
    expect(runtime.loadedPlans.last.reloadPosition, const Duration(seconds: 8));
    await waitForSessionCondition(() => session.currentSnapshot.phase == PlaybackPhase.ready);
    final live = sessionPlan('live', kind: PlaybackTimelineKind.live);
    await owner.load(live, start: PlaybackStartPolicy.play);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, position: Duration(seconds: 500)),
    );
    await owner.recover(live);
    expect(runtime.loadedPlans.last.startPosition, isNull);
    expect(runtime.loadedPlans.last.reloadPosition, isNull);
    owner.close();
    await session.shutdown();
  });

  test('暂停期间恢复延期，恢复用户播放意图后才提交加载', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      monotonicNow: () => now,
    );
    final owner = session.attach();
    final plan = sessionPlan('movie');
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);

    expect((await owner.recover(plan)).outcome, LoadOutcome.deferred);
    expect(runtime.loadedKeys, ['movie']);

    now = const Duration(seconds: 40);
    await owner.setPlaying(true);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, videoProgressing: false),
    );
    await waitForSessionCondition(
      () =>
          runtime.loadedKeys.length == 2 &&
          session.currentSnapshot.phase == PlaybackPhase.ready,
    );
    expect(runtime.loadedKeys, ['movie', 'movie']);
    expect(session.currentSnapshot.phase, PlaybackPhase.ready);

    owner.close();
    await session.shutdown();
  });

  test('恢复预算跨 loadId 累计，连续健康十秒后才重置', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      monotonicNow: () => now,
    );
    final owner = session.attach();
    final plan = sessionPlan('movie');
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);
    await owner.setPlaying(true);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, videoProgressing: false),
    );

    for (var i = 0; i < 3; i++) {
      now = Duration(seconds: [0, 10, 25][i]);
      final result = await owner.recover(plan);
      expect(
        result.outcome,
        LoadOutcome.ready,
        reason: 'recovery attempt $i: ${result.failure?.cause}',
      );
    }
    expect(runtime.loadedKeys, ['movie', 'movie', 'movie', 'movie']);

    now = const Duration(seconds: 26);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, videoProgressing: true),
    );
    now = const Duration(seconds: 36);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, videoProgressing: true),
    );

    expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
    expect(runtime.loadedKeys, ['movie', 'movie', 'movie', 'movie', 'movie']);

    owner.close();
    await session.shutdown();
  });

  test('恢复加载前后的健康观测不能合并为连续十秒', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      monotonicNow: () => now,
    );
    final owner = session.attach();
    final healthyLoads = <Object?>[];
    final subscription = session.trace
        .where((event) => event.name == 'recovery.healthy')
        .listen((event) => healthyLoads.add(event.fields['loadId']));
    addTearDown(() async {
      await subscription.cancel();
      owner.close();
      await session.shutdown();
    });
    final plan = sessionPlan('movie');
    expect(
      (await owner.load(plan, start: PlaybackStartPolicy.play)).outcome,
      LoadOutcome.ready,
    );
    for (final second in [0, 10]) {
      now = Duration(seconds: second);
      expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
    }

    const healthy = PlaybackActual(playing: true, videoProgressing: true);
    now = const Duration(seconds: 19);
    runtime.emitActual(session.loadId, healthy);
    runtime.onLoad = (plan, context, _) async {
      now = const Duration(seconds: 29);
      runtime.emitActual(context.loadId, healthy);
      return preparedSessionLoad(context, plan);
    };
    now = const Duration(seconds: 25);
    expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
    expect(healthyLoads, isEmpty);
    now = const Duration(seconds: 38);
    runtime.emitActual(session.loadId, healthy);
    expect(healthyLoads, isEmpty);
    now = const Duration(seconds: 39);
    runtime.emitActual(session.loadId, healthy);
    expect(healthyLoads, [session.loadId]);
  });

  for (final interruption in ['页面抑制', '原生 seek']) {
    test('连续十秒的健康观测不能跨过$interruption', () async {
      var now = Duration.zero;
      final runtime = FakeSessionRuntime();
      final session = PlaybackSession(
        runtime: runtime,
        monotonicNow: () => now,
      );
      final owner = session.attach();
      final healthyLoads = <Object?>[];
      final subscription = session.trace
          .where((event) => event.name == 'recovery.healthy')
          .listen((event) => healthyLoads.add(event.fields['loadId']));
      addTearDown(() async {
        await subscription.cancel();
        owner.close();
        await session.shutdown();
      });
      final plan = sessionPlan('movie');
      expect(
        (await owner.load(plan, start: PlaybackStartPolicy.play)).outcome,
        LoadOutcome.ready,
      );
      expect((await owner.recover(plan)).outcome, LoadOutcome.ready);

      const healthy = PlaybackActual(playing: true, videoProgressing: true);
      now = const Duration(seconds: 1);
      runtime.emitActual(session.loadId, healthy);
      now = const Duration(seconds: 6);
      if (interruption == '页面抑制') {
        final token = owner.acquireInhibitor(PlaybackInhibitorSource.system)!;
        await session.synchronizePlaybackIntent();
        now = const Duration(seconds: 7);
        await owner.releaseInhibitor(token);
      } else {
        runtime.emitActual(
          session.loadId,
          const PlaybackActual(
            playing: true,
            seeking: true,
            videoProgressing: true,
          ),
        );
        now = const Duration(seconds: 7);
      }
      runtime.emitActual(session.loadId, healthy);
      now = const Duration(seconds: 11);
      runtime.emitActual(session.loadId, healthy);
      expect(healthyLoads, isEmpty);
      now = const Duration(seconds: 17);
      runtime.emitActual(session.loadId, healthy);
      expect(healthyLoads, [session.loadId]);
    });
  }

  for (final scenario in [
    (
      name: '音视频共同健康',
      hasAudio: true,
      hasVideo: true,
      audioOnly: false,
      audio: true,
      video: true,
      resets: true,
    ),
    (
      name: '音频故障而画面健康',
      hasAudio: true,
      hasVideo: true,
      audioOnly: false,
      audio: false,
      video: true,
      resets: false,
    ),
    (
      name: '画面故障而音频健康',
      hasAudio: true,
      hasVideo: true,
      audioOnly: false,
      audio: true,
      video: false,
      resets: false,
    ),
    (
      name: '双轨同时故障',
      hasAudio: true,
      hasVideo: true,
      audioOnly: false,
      audio: false,
      video: false,
      resets: false,
    ),
    (
      name: '只听音频时忽略视频停滞',
      hasAudio: true,
      hasVideo: true,
      audioOnly: true,
      audio: true,
      video: false,
      resets: true,
    ),
    (
      name: '只听音频时忽略未知视频轨道',
      hasAudio: true,
      hasVideo: null,
      audioOnly: true,
      audio: true,
      video: null,
      resets: true,
    ),
    (
      name: '纯视频忽略不存在的音轨',
      hasAudio: false,
      hasVideo: true,
      audioOnly: false,
      audio: null,
      video: true,
      resets: true,
    ),
    (
      name: '音视频模式音轨未知不能确认健康',
      hasAudio: null,
      hasVideo: true,
      audioOnly: false,
      audio: true,
      video: true,
      resets: false,
    ),
  ]) {
    testWidgets('恢复预算按所需轨道判断：${scenario.name}', (tester) async {
      var now = Duration.zero;
      final runtime = FakeSessionRuntime()
        ..onLoad = (plan, context, _) async => PlaybackRuntimeLoadResult(
          loaded: true,
          output: preparedSessionLoad(context, plan).output,
          capabilities: PlaybackCapabilities(
            hasAudio: scenario.hasAudio,
            hasVideo: scenario.hasVideo,
          ),
        );
      final session = PlaybackSession(
        runtime: runtime,
        monotonicNow: () => now,
      );
      final owner = session.attach();
      try {
        final plan = sessionPlan('tracks', audioOnly: scenario.audioOnly);
        expect(
          (await owner.load(plan, start: PlaybackStartPolicy.play)).outcome,
          LoadOutcome.ready,
        );
        for (var i = 0; i < 3; i++) {
          now = Duration(seconds: [0, 10, 25][i]);
          expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
        }
        void observe() => runtime.emitActual(
          session.loadId,
          PlaybackActual(
            playing: true,
            buffering: false,
            audioProgressing: scenario.audio,
            videoProgressing: scenario.video,
          ),
        );
        now = const Duration(seconds: 26);
        observe();
        now = const Duration(seconds: 36);
        observe();
        final result = await owner.recover(plan);
        expect(
          result.outcome,
          scenario.resets ? LoadOutcome.ready : LoadOutcome.failed,
        );
        expect(runtime.loadedKeys, hasLength(scenario.resets ? 5 : 4));
        if (!scenario.resets) {
          expect(result.failure?.operation, 'automatic-recovery');
        }
      } finally {
        owner.close();
        await session.shutdown();
      }
    });
  }

  test('连续故障恢复预算按有效播放时间耗尽，不因经过三十秒自动重开', () async {
    var now = Duration.zero;
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(
      runtime: runtime,
      monotonicNow: () => now,
    );
    final owner = session.attach();
    final plan = sessionPlan('movie');
    expect((await owner.load(plan)).outcome, LoadOutcome.ready);
    await owner.setPlaying(true);
    runtime.emitActual(
      session.loadId,
      const PlaybackActual(playing: true, videoProgressing: false),
    );

    for (var i = 0; i < 3; i++) {
      now = Duration(seconds: [0, 10, 25][i]);
      expect((await owner.recover(plan)).outcome, LoadOutcome.ready);
    }
    now = const Duration(seconds: 30);
    final exhausted = await owner.recover(plan);
    expect(exhausted.outcome, LoadOutcome.failed);
    expect(runtime.loadedKeys, ['movie', 'movie', 'movie', 'movie']);

    owner.close();
    await session.shutdown();
  });

  test('交接屏障等待 loading 中旧媒体的实际暂停', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('before'), start: PlaybackStartPolicy.play);
    final paused = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSetPlaying = (playing, _, _) => playing
        ? Future.value(const PlaybackRuntimeCommandResult())
        : paused.future;
    final resolved = Completer<PlaybackPlan?>();
    final loading = owner.query(
      (_) => resolved.future,
      start: PlaybackStartPolicy.play,
    );
    final hold = session.acquireSessionInhibitor(
      PlaybackInhibitorSource.audioFocus,
    )!;
    var synchronized = false;
    final sync = session.synchronizePlaybackIntent()
      ..then((_) => synchronized = true);
    await Future<void>.delayed(Duration.zero);
    expect(synchronized, isFalse);
    paused.complete(const PlaybackRuntimeCommandResult());
    expect((await sync).outcome, CommandOutcome.applied);
    resolved.complete(sessionPlan('after'));
    await loading;
    await session.releaseSessionInhibitor(hold);
    owner.close();
    await session.shutdown();
  });

  test('交接屏障等待仅解析来源进入 idle 后的旧媒体暂停', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    await owner.load(sessionPlan('before'), start: PlaybackStartPolicy.play);
    final paused = Completer<PlaybackRuntimeCommandResult>();
    runtime.onSetPlaying = (playing, _, _) => playing
        ? Future.value(const PlaybackRuntimeCommandResult())
        : paused.future;
    final query = await owner.query(
      (_) async => sessionPlan('metadata-only'),
      shouldLoad: () => false,
    );
    expect(query.outcome, LoadOutcome.noMedia);
    expect(session.currentSnapshot.phase, PlaybackPhase.idle);
    session.acquireSessionInhibitor(PlaybackInhibitorSource.audioFocus);
    var synchronized = false;
    final sync = session.synchronizePlaybackIntent()
      ..then((_) => synchronized = true);
    await Future<void>.delayed(Duration.zero);
    expect(synchronized, isFalse);
    paused.complete(const PlaybackRuntimeCommandResult());
    expect((await sync).outcome, CommandOutcome.applied);
    owner.close();
    await session.shutdown();
  });

  test('交接屏障等待在途原生加载结束', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final opened = Completer<PlaybackRuntimeLoadResult>();
    runtime.onLoad = (_, _, _) => opened.future;
    final loading = owner.load(
      sessionPlan('opening'),
      start: PlaybackStartPolicy.play,
    );
    await waitForSessionCondition(() => runtime.loadedKeys.isNotEmpty);
    session.acquireSessionInhibitor(PlaybackInhibitorSource.audioFocus);
    var synchronized = false;
    final sync = session.synchronizePlaybackIntent()
      ..then((_) => synchronized = true);
    await Future<void>.delayed(Duration.zero);
    expect(synchronized, isFalse);
    opened.complete(
      const PlaybackRuntimeLoadResult(
        loaded: true,
        output: PlaybackOutputPreparation(
          strategy: PlaybackOutputStrategy.prepared,
          evidence: 'synthetic paused open',
          outputEpoch: 1,
        ),
      ),
    );
    await loading;
    expect((await sync).outcome, CommandOutcome.applied);
    expect(runtime.playCalls, everyElement(isFalse));
    owner.close();
    await session.shutdown();
  });

  for (final closing in [false, true]) {
    testWidgets('交接屏障跨加载与${closing ? '关闭' : '暂停'}共用命令总时限', (tester) async {
      final runtime = FakeSessionRuntime();
      final opened = Completer<PlaybackRuntimeLoadResult>();
      final paused = Completer<PlaybackRuntimeCommandResult>();
      final closed = Completer<PlaybackShutdownResult>();
      runtime
        ..onLoad = ((_, _, _) => opened.future)
        ..onSetPlaying = ((_, _, _) => paused.future)
        ..onShutdown = (() => closed.future);
      final session = PlaybackSession(
        runtime: runtime,
        commandBudget: const Duration(seconds: 5),
        monotonicNow: () => Duration(
          microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
        ),
      );
      final owner = session.attach();
      final loading = owner.load(sessionPlan('opening'));
      await tester.pump();
      session.acquireSessionInhibitor(PlaybackInhibitorSource.audioFocus);
      CommandResult? synchronized;
      final sync = session.synchronizePlaybackIntent()
        ..then((value) => synchronized = value);
      await tester.pump(const Duration(seconds: 3));
      expect(synchronized, isNull);
      opened.complete(
        const PlaybackRuntimeLoadResult(
          loaded: true,
          output: PlaybackOutputPreparation(
            strategy: PlaybackOutputStrategy.prepared,
            evidence: 'synthetic paused open',
            outputEpoch: 1,
          ),
        ),
      );
      await tester.pump();
      if (closing) {
        session.shutdown();
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 2));
      expect(synchronized?.outcome, CommandOutcome.failed);
      expect(synchronized?.failure?.category, PlaybackFailureCategory.timeout);
      paused.complete(const PlaybackRuntimeCommandResult());
      runtime.completeRelease();
      closed.complete(const PlaybackShutdownResult.released());
      await tester.pump();
      await sync;
      await loading;
      owner.close();
      await session.shutdown();
      await tester.pump();
    });
  }

  test('交接屏障等待关闭释放并保留清理失败结果', () async {
    final closed = Completer<PlaybackShutdownResult>();
    final runtime = FakeSessionRuntime()..onShutdown = () => closed.future;
    final session = PlaybackSession(runtime: runtime);
    session.attach().close();
    var synchronized = false;
    final sync = session.synchronizePlaybackIntent()
      ..then((_) => synchronized = true);
    await Future<void>.delayed(Duration.zero);
    expect(synchronized, isFalse);
    const failure = PlaybackFailure(
      category: PlaybackFailureCategory.disposal,
      operation: 'shutdown',
      stage: PlaybackStage.closing,
      recoverable: false,
      cause: 'synthetic release failure',
    );
    closed.complete(const PlaybackShutdownResult.cleanupIncomplete(failure));
    final result = await sync;
    expect(result.outcome, CommandOutcome.failed);
    expect(result.failure, same(failure));
    runtime.completeRelease();
    await waitForSessionCondition(() => session.currentSnapshot.phase == PlaybackPhase.disposed);
  });

  test('shutdown deadline可先结算cleanupIncomplete，released迟到后仍完成资源释放', () async {
    final runtime = FakeSessionRuntime()
      ..onShutdown = () async => const PlaybackShutdownResult.cleanupIncomplete(
        PlaybackFailure(
          category: PlaybackFailureCategory.timeout,
          operation: 'shutdown',
          stage: PlaybackStage.closing,
          recoverable: false,
          cause: 'fake delayed release',
        ),
      );
    final session = PlaybackSession(runtime: runtime);
    session.attach().close();
    final result = await session.shutdown();
    expect(result.outcome, PlaybackShutdownOutcome.cleanupIncomplete);
    expect(session.currentSnapshot.phase, PlaybackPhase.closing);

    runtime.completeRelease();
    await waitForSessionCondition(() => session.currentSnapshot.phase == PlaybackPhase.disposed);
  });

  test('shutdown 不因暂停的 snapshot stream 拖住原生 released', () async {
    final runtime = FakeSessionRuntime();
    final session = PlaybackSession(runtime: runtime);
    final owner = session.attach();
    final subscription = owner.snapshots.listen((_) {})..pause();

    owner.close();
    final shutdown = await session.shutdown().timeout(
      const Duration(seconds: 1),
    );
    expect(shutdown.outcome, PlaybackShutdownOutcome.released);
    expect(session.currentSnapshot.phase, PlaybackPhase.disposed);
    await subscription.cancel();
  });
}
