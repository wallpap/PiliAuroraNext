import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';

void main() {
  late ShutdownTimerService service;
  late int exits;
  final messages = <String>[];

  setUp(() {
    exits = 0;
    messages.clear();
    service = ShutdownTimerService(
      exit: () async => exits++,
      notify: messages.add,
    );
  });

  void check(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        service.reset();
        await tester.pump(const Duration(milliseconds: 250));
      }
    });
  }

  Future<void> expire(WidgetTester tester) async {
    service.startShutdownTimer(1);
    expect(messages.last, '设置 1分钟 后定时关闭');
    messages.clear();
    await tester.pump(const Duration(minutes: 1));
  }

  check('定时暂停等待控制回执后才提示成功', (tester) async {
    final paused = Completer<void>();
    var calls = 0;
    service.bindPlayer(
      pause: () {
        calls++;
        return paused.future;
      },
      isPlaying: () => true,
    );
    await expire(tester);
    expect(calls, 1);
    expect(messages, isEmpty);
    paused.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(messages, contains('定时时间已到，已暂停'));
  });

  for (final synchronous in [true, false]) {
    check('定时暂停消费${synchronous ? '同步' : '异步'}错误并提示失败', (tester) async {
      final cause = StateError('https://private.example/?token=secret');
      service.bindPlayer(
        pause: () {
          if (synchronous) throw cause;
          return Future<void>.error(cause);
        },
        isPlaying: () => true,
      );
      await expire(tester);
      expect(messages, contains('定时暂停失败，请手动暂停'));
      expect(messages.join(), isNot(contains('secret')));
      expect(messages, isNot(contains('定时时间已到，已暂停')));
    });
  }

  check('取消或重设定时后不发布旧暂停的迟到结果', (tester) async {
    for (final failed in [false, true]) {
      final paused = Completer<void>();
      service.bindPlayer(pause: () => paused.future, isPlaying: () => true);
      await expire(tester);
      service.reset();
      if (failed) {
        paused.completeError(StateError('synthetic late pause failure'));
      } else {
        paused.complete();
      }
      await tester.pump();
      expect(messages, isEmpty);
    }
  });

  for (final action in ShutdownAction.values) {
    check('只有等候的播放实例可完成 ${action.name} 定时动作', (tester) async {
      service
        ..action = action
        ..waitUntilCompleted = true;
      final old = service.bindPlayer(pause: () async {}, isPlaying: () => true);
      await expire(tester);
      expect(service.isWaiting, isTrue);
      final current = service.bindPlayer(
        pause: () async {},
        isPlaying: () => true,
      );
      expect(service.isWaiting, isFalse);
      await expire(tester);
      old.dispose();
      expect(old.complete(), isFalse);
      expect(service.isWaiting, isTrue);
      expect(exits, 0);
      expect(messages, isEmpty);
      expect(current.complete(), isTrue);
      expect(current.complete(), isFalse);
      expect(service.isWaiting, isFalse);
      expect(exits, action == .exit ? 1 : 0);
      expect(
        messages,
        action == .pause ? ['定时时间已到，已暂停'] : isEmpty,
      );
    });
  }

  check('音频接管和旧实例释放不会误用视频绑定或清除新定时', (tester) async {
    final paused = Completer<void>();
    var videoPauses = 0;
    final video = service.bindPlayer(
      pause: () async {
        videoPauses++;
      },
      isPlaying: () => true,
    );
    final oldAudio = service.bindPlayer(
      pause: () => paused.future,
      isPlaying: () => true,
      independentAudio: true,
    );
    await expire(tester);
    final audio = service.bindPlayer(
      pause: () async {},
      isPlaying: () => true,
      independentAudio: true,
    );
    paused.complete();
    await tester.pump();
    expect(messages, isEmpty);
    expect(videoPauses, 0);

    service
      ..waitUntilCompleted = true
      ..startShutdownTimer(1);
    oldAudio.dispose();
    expect(service.isActive, isTrue);
    await tester.pump(const Duration(minutes: 1));
    expect(video.complete(), isFalse);
    expect(service.isWaiting, isTrue);
    audio.dispose();
    expect(service.isWaiting, isFalse);
    expect(audio.complete(), isFalse);
  });

  check('直播立即处理定时动作，继承的等待选项不会阻塞', (tester) async {
    var pauses = 0;
    service
      ..waitUntilCompleted = true
      ..bindPlayer(
        pause: () async {
          pauses++;
        },
        isPlaying: () => true,
        supportsCompletion: false,
      );
    await expire(tester);
    expect(service.isWaiting, isFalse);
    expect(pauses, 1);
    expect(messages, ['定时时间已到，已暂停']);
    service.action = .exit;
    await expire(tester);
    expect(service.isWaiting, isFalse);
    expect(exits, 1);
  });

  check('应用释放定时器后旧弹层与播放租约无法触发退出', (tester) async {
    service.action = .exit;
    final binding = service.bindPlayer(
      pause: () async {},
      isPlaying: () => true,
    );
    service
      ..startShutdownTimer(1)
      ..dispose();
    messages.clear();

    service.startShutdownTimer(1);
    await tester.pump(const Duration(minutes: 1));
    expect(binding.complete(), isFalse);
    expect(exits, 0);
    expect(messages, isEmpty);
  });
}
