import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/diagnostics/player_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('disposed players never enter native property reads', () {
    expect(readMpvProperty(_DisposedNativePlayer(), 'hwdec-current'), isNull);
  });

  test('慢帧与播放器采样并存时保留弹幕计数和诊断状态', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pili-player-diag-',
    );
    final diagnostics = Diagnostics.instance;
    await diagnostics.initialize(directory: directory);
    final player = _SnapshotPlayer();
    player.state.duration = const Duration(seconds: 87);
    final playerDiagnostics = PlayerDiagnostics(player);
    final detachDanmaku = diagnostics.register(
      'danmaku.fixture',
      () => {'elements': 6755},
    );
    try {
      await diagnostics.configure(tracing: true);
      await Future<void>.delayed(Duration.zero);
      TestWidgetsFlutterBinding.instance.platformDispatcher.onReportTimings!(
        List.generate(
          16,
          (_) => FrameTiming(
            vsyncStart: 0,
            buildStart: 1000,
            buildFinish: 21000,
            rasterStart: 22000,
            rasterFinish: 52000,
            rasterFinishWallTime: 1700000000000000,
          ),
        ),
      );
      diagnostics.capture();
      final sources = diagnostics.latest!['sources'] as Map;
      expect(sources['danmaku.fixture'], containsPair('elements', 6755));
      expect(
        diagnostics.latest!['diagnostics'],
        containsPair('droppedRecords', 0),
      );
      expect(
        sources[playerDiagnostics.playerId],
        containsPair('hwdec-current', 'mediacodec'),
      );
      expect(playerDiagnostics.snapshot(), contains('track-list'));
      expect(playerDiagnostics.snapshot(), containsPair('durationMs', 87000));
      expect(
        playerDiagnostics.snapshot(detailed: false),
        containsPair('durationMs', 87000),
      );
      player.logController.add(
        const PlayerLog(prefix: 'vd', level: 'error', text: 'native failure'),
      );
      player.errorController.add('native failure');
      await Future<void>.delayed(Duration.zero);
      player.errorController.add('independent failure');
      await Future<void>.delayed(Duration.zero);
      final events = diagnostics.recentEvents;
      final created = events.singleWhere(
        (event) => event.message == 'player.created',
      );
      expect(
        created.details,
        containsPair('playerId', playerDiagnostics.playerId),
      );
      expect(created.details, isNot(contains('durationMs')));
      final native = events.singleWhere(
        (event) => event.message == 'native failure',
      );
      final context =
          events
                  .singleWhere(
                    (event) => event.message == 'mpv.error.context',
                  )
                  .details
              as Map;
      expect(context['mpvErrorSequence'], native.sequence);
      expect(context['state'], containsPair('durationMs', 87000));
      final standalone = events.singleWhere(
        (event) => event.message == 'playback.error',
      );
      expect(standalone.details, containsPair('error', 'independent failure'));
    } finally {
      detachDanmaku();
      playerDiagnostics.dispose();
      await player.logController.close();
      await player.errorController.close();
      diagnostics.dispose();
      await diagnostics.flush();
      await directory.delete(recursive: true);
    }
  });
}

class _DisposedNativePlayer implements NativePlayer {
  @override
  bool get disposed => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Disposed player must not access native state');
}

class _SnapshotPlayer implements NativePlayer {
  @override
  bool get disposed => true;
  @override
  final state = PlayerState();
  @override
  final onLoadHooks = <Future<void> Function()>[];
  @override
  final onUnloadHooks = <Future<void> Function()>[];
  @override
  final logController = StreamController<PlayerLog>();
  @override
  final errorController = StreamController<String>();
  @override
  late final stream = _SnapshotStreams(
    logController.stream,
    errorController.stream,
  );
  @override
  Stream<String?> observeProperty(String name) => Stream.value(
    name == 'hwdec-current' ? 'mediacodec' : 'fixture-$name',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native operation: ${invocation.memberName}');
}

class _SnapshotStreams implements PlayerStream {
  _SnapshotStreams(this.log, this.error);

  @override
  final Stream<PlayerLog> log;
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<VideoParams> get videoParams => const Stream.empty();
  @override
  final Stream<String> error;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected player stream: ${invocation.memberName}');
}
