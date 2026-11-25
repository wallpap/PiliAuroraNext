import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';
import 'package:pili_aurora_next/services/audio_session.dart';

import '../plugin/pl_player/playback/playback_session_fixture.dart';

class _PlaybackController implements PlPlayerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionPlaybackController extends _PlaybackController {
  final runtime = FakeSessionRuntime();
  late final playback = PlaybackSession(runtime: runtime);

  @override
  PlaybackOwner? activePlaybackOwner;

  PlaybackOwner attachOwner() => activePlaybackOwner = playback.attach();

  @override
  PlaybackSnapshot get currentPlaybackSnapshot => playback.currentSnapshot;

  @override
  PlaybackInhibitorToken? acquireSessionInhibitor(
    PlaybackInhibitorSource source,
  ) => playback.acquireSessionInhibitor(source);

  @override
  Future<CommandResult> releaseSessionInhibitor(
    PlaybackInhibitorToken token,
  ) => playback.releaseSessionInhibitor(token);

  @override
  Future<CommandResult> synchronizePlaybackIntent() =>
      playback.synchronizePlaybackIntent();
}

class _AudioSession implements AudioSession {
  Future<void> Function()? configureSession;
  Future<bool> Function(bool)? changeActivation;
  int configurations = 0;
  int interruptionSubscriptions = 0;
  int noisySubscriptions = 0;
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final noisy = StreamController<void>.broadcast();
  final activations = <bool>[];

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configurations++;
    await configureSession?.call();
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream {
    interruptionSubscriptions++;
    return interruptions.stream;
  }

  @override
  Stream<void> get becomingNoisyEventStream {
    noisySubscriptions++;
    return noisy.stream;
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    return changeActivation?.call(active) ?? active;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> dispose() async {
    await interruptions.close();
    await noisy.close();
  }
}

void main() {
  test('构造不启动后台初始化，激活等待同一配置且事件只订阅一次', () async {
    final configured = Completer<void>();
    final session = _AudioSession()..configureSession = () => configured.future;
    var loads = 0;
    final handler = AudioSessionHandler(
      loadSession: () async {
        loads++;
        return session;
      },
    );
    addTearDown(session.dispose);
    addTearDown(handler.dispose);
    expect(loads, 0);
    final initialized = handler.initSession();
    expect(handler.initSession(), same(initialized));
    final activated = handler.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(session.activations, isEmpty);
    expect(session.interruptionSubscriptions, 0);
    configured.complete();
    await initialized;
    expect(await activated, isTrue);
    expect(await handler.setActive(false), isFalse);
    expect(loads, 1);
    expect(session.configurations, 1);
    expect(session.activations, [true, false]);
    expect(session.interruptionSubscriptions, 1);
    expect(session.noisySubscriptions, 1);
  });

  test('会话配置失败沿初始化 Future 返回，保留原因与堆栈并允许重试', () async {
    final cause = StateError('synthetic session configuration failure');
    final stack = StackTrace.fromString('#0 audio.configure');
    final session = _AudioSession()
      ..configureSession = () async => Error.throwWithStackTrace(cause, stack);
    final handler = AudioSessionHandler(loadSession: () async => session);
    addTearDown(session.dispose);
    addTearDown(handler.dispose);
    try {
      await handler.initSession();
      fail('configuration should fail');
    } catch (error, trace) {
      expect(error, same(cause));
      expect(trace.toString(), stack.toString());
    }
    expect(session.interruptionSubscriptions, 0);
    expect(session.activations, isEmpty);
    session.configureSession = null;
    expect(await handler.setActive(true), isTrue);
    expect(session.configurations, 2);
    expect(session.interruptionSubscriptions, 1);
    expect(session.noisySubscriptions, 1);
  });

  test('释放应用音频会话时取消两类原生订阅并交还已取得的焦点', () async {
    final session = _AudioSession();
    addTearDown(session.dispose);
    final handler = AudioSessionHandler(loadSession: () async => session);
    expect(await handler.setActive(true), isTrue);
    expect(session.interruptions.hasListener, isTrue);
    expect(session.noisy.hasListener, isTrue);

    final released = handler.dispose();
    expect(handler.dispose(), same(released));
    await released;
    expect(session.interruptions.hasListener, isFalse);
    expect(session.noisy.hasListener, isFalse);
    expect(await handler.setActive(true), isFalse);
    expect(session.activations, [true, false]);
  });

  test('应用释放时尚未完成的原生配置不能再注册监听或获取焦点', () async {
    final configured = Completer<void>();
    final session = _AudioSession()..configureSession = () => configured.future;
    addTearDown(session.dispose);
    final handler = AudioSessionHandler(loadSession: () async => session);
    final activating = handler.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(session.configurations, 1);

    await handler.dispose();
    configured.complete();
    expect(await activating, isFalse);
    expect(session.interruptionSubscriptions, 0);
    expect(session.noisySubscriptions, 0);
    expect(session.activations, isEmpty);
  });

  test('旧播放器解绑后保留当前焦点所有者，当前播放器解绑后允许接管', () async {
    final session = _AudioSession();
    final handler = AudioSessionHandler(loadSession: () async => session);
    addTearDown(session.dispose);
    addTearDown(handler.dispose);

    final previous = _PlaybackController();
    final current = _PlaybackController();
    final next = _PlaybackController();
    handler
      ..attachPlaybackController(previous)
      ..attachPlaybackController(current)
      ..detachPlaybackController(previous);

    await handler.changeVideoActive(next, true);
    expect(session.activations, isEmpty);
    await handler.changeVideoActive(current, true);
    expect(session.activations, [true]);

    handler.detachPlaybackController(current);
    await handler.changeVideoActive(next, false);
    expect(session.activations, [true, false]);
  });

  test('Android 永久失焦跨视频保留，手动申请成功后解除系统抑制', () async {
    final session = _AudioSession();
    final handler = AudioSessionHandler(
      loadSession: () async => session,
      androidFocusLifecycle: true,
    );
    final controller = _SessionPlaybackController();
    addTearDown(session.dispose);
    addTearDown(controller.playback.shutdown);
    addTearDown(handler.dispose);
    handler.attachPlaybackController(controller);
    final first = controller.attachOwner();
    await first.load(sessionPlan('first'), start: PlaybackStartPolicy.play);
    expect(await handler.changeVideoActive(controller, true), isTrue);

    session.interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.unknown),
    );
    await waitForSessionCondition(() => !controller.runtime.playCalls.last);
    final second = controller.attachOwner();
    final loaded = await second.load(
      sessionPlan('other-origin'),
      start: PlaybackStartPolicy.play,
    );
    expect(loaded.outcome, LoadOutcome.ready);
    expect(controller.currentPlaybackSnapshot.intent.playing, isTrue);
    expect(controller.runtime.playCalls.last, isFalse);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));

    expect(
      await handler.changeVideoActive(
        controller,
        true,
        allowFocusReacquisition: false,
      ),
      isTrue,
    );
    expect(session.activations, [true]);
    session.interruptions.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));

    session.changeActivation = (active) async => !active;
    expect(await handler.changeVideoActive(controller, true), isFalse);
    expect(session.activations, [true, true, false]);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));
    expect(controller.runtime.playCalls.last, isFalse);

    session.changeActivation = null;
    expect(await handler.changeVideoActive(controller, true), isTrue);
    expect(controller.currentPlaybackSnapshot.inhibitors, isEmpty);
    expect(controller.runtime.playCalls.last, isTrue);
  });

  test('Android 暂时失焦不提前恢复；主动放弃请求后可以再次申请', () async {
    final session = _AudioSession()..changeActivation = (_) async => true;
    final handler = AudioSessionHandler(
      loadSession: () async => session,
      androidFocusLifecycle: true,
    );
    final controller = _SessionPlaybackController();
    addTearDown(session.dispose);
    addTearDown(controller.playback.shutdown);
    addTearDown(handler.dispose);
    handler.attachPlaybackController(controller);
    final owner = controller.attachOwner();
    await owner.load(sessionPlan('video'), start: PlaybackStartPolicy.play);
    await handler.changeVideoActive(controller, true);
    final playing = controller.runtime.playCalls;

    session.interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await waitForSessionCondition(() => !playing.last);
    await handler.changeVideoActive(controller, true);
    expect(playing.last, isFalse);
    session.interruptions.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await waitForSessionCondition(() => playing.last);

    session.interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await waitForSessionCondition(() => !playing.last);
    await owner.setPlaying(false);
    await handler.changeVideoActive(controller, false);
    expect(controller.currentPlaybackSnapshot.intent.playing, isFalse);
    expect(playing.last, isFalse);
    await owner.setPlaying(true);
    await handler.changeVideoActive(controller, true);
    expect(controller.currentPlaybackSnapshot.inhibitors, isEmpty);
    expect(playing.last, isTrue);
  });

  test('Android 迟到焦点回执不能解除更新的永久失焦', () async {
    final session = _AudioSession();
    final handler = AudioSessionHandler(
      loadSession: () async => session,
      androidFocusLifecycle: true,
    );
    final controller = _SessionPlaybackController();
    addTearDown(session.dispose);
    addTearDown(controller.playback.shutdown);
    addTearDown(handler.dispose);
    handler.attachPlaybackController(controller);
    final owner = controller.attachOwner();
    await owner.load(sessionPlan('video'), start: PlaybackStartPolicy.play);
    await handler.changeVideoActive(controller, true);

    final lost = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
    session.interruptions.add(lost);
    await waitForSessionCondition(() => !controller.runtime.playCalls.last);
    final pending = Completer<bool>();
    session.changeActivation = (_) => pending.future;
    final request = handler.changeVideoActive(controller, true);
    await waitForSessionCondition(() => session.activations.length == 2);
    session.interruptions.add(lost);
    await Future<void>.delayed(Duration.zero);
    pending.complete(true);
    await request;
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));
    expect(controller.runtime.playCalls.last, isFalse);

    session.changeActivation = null;
    await handler.changeVideoActive(controller, true);
    expect(controller.currentPlaybackSnapshot.inhibitors, isEmpty);
    expect(controller.runtime.playCalls.last, isTrue);
  });

  test('Android 旧播放所有者的获焦回执不能恢复新视频', () async {
    final session = _AudioSession();
    final handler = AudioSessionHandler(
      loadSession: () async => session,
      androidFocusLifecycle: true,
    );
    final controller = _SessionPlaybackController();
    addTearDown(session.dispose);
    addTearDown(controller.playback.shutdown);
    addTearDown(handler.dispose);
    handler.attachPlaybackController(controller);
    final first = controller.attachOwner();
    await first.load(sessionPlan('first'), start: PlaybackStartPolicy.play);
    await handler.changeVideoActive(controller, true);
    session.interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.unknown),
    );
    await waitForSessionCondition(() => !controller.runtime.playCalls.last);

    final pending = Completer<bool>();
    session.changeActivation = (active) =>
        active ? pending.future : Future.value(true);
    final request = handler.changeVideoActive(
      controller,
      true,
      isCurrent: () => first.isActive,
    );
    await waitForSessionCondition(() => session.activations.length == 2);
    final second = controller.attachOwner();
    await second.load(sessionPlan('second'), start: PlaybackStartPolicy.play);
    pending.complete(true);
    await request;
    expect(session.activations, [true, true, false]);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));
    expect(controller.runtime.playCalls.last, isFalse);

    session.changeActivation = null;
    expect(await handler.changeVideoActive(controller, true), isTrue);
    expect(controller.currentPlaybackSnapshot.inhibitors, isEmpty);
    expect(controller.runtime.playCalls.last, isTrue);
  });

  test('独立音频重新获焦，独立租约仍保持视频暂停直到实际释放', () async {
    final session = _AudioSession()..changeActivation = (_) async => true;
    final handler = AudioSessionHandler(
      loadSession: () async => session,
      androidFocusLifecycle: true,
    );
    final controller = _SessionPlaybackController();
    addTearDown(session.dispose);
    addTearDown(controller.playback.shutdown);
    addTearDown(handler.dispose);
    handler.attachPlaybackController(controller);
    final owner = controller.attachOwner();
    await owner.load(sessionPlan('video'), start: PlaybackStartPolicy.play);
    final playing = <bool>[];
    final lease = handler.acquireIndependentPlayer(
      setPlaying: (value) async => playing.add(value),
      volume: () => 100,
      volumeRevision: () => 0,
      setVolume: (_) async {},
    );
    await lease.setPlaying(true);
    expect(playing.last, isTrue);
    expect(controller.runtime.playCalls.last, isFalse);

    session.interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.unknown),
    );
    await waitForSessionCondition(() => !playing.last);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(2));
    await lease.setPlaying(true);
    expect(playing.last, isTrue);
    expect(controller.currentPlaybackSnapshot.inhibitors, hasLength(1));
    expect(controller.runtime.playCalls.last, isFalse);

    await lease.close(() async {});
    expect(controller.currentPlaybackSnapshot.inhibitors, isEmpty);
    expect(controller.runtime.playCalls.last, isTrue);
  });
}
