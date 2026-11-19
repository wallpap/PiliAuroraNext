import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/services/audio_session.dart';

class _PlaybackController implements PlPlayerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioSession implements AudioSession {
  Future<void> Function()? configureSession;
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
    return active;
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
}
