import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_source.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';

PlaybackPlan sessionPlan(
  String key, {
  PlaybackSeekPolicy seekPolicy = PlaybackSeekPolicy.allowed,
  PlaybackTimelineKind kind = PlaybackTimelineKind.onDemand,
  List<String>? candidates,
  bool audioOnly = false,
  Duration? duration = const Duration(seconds: 10),
}) => PlaybackPlan(
  contentKey: key,
  source: PlaybackSourceSnapshot.fromDataSource(
    NetworkSource(
      videoSource: candidates?.first ?? 'https://example.test/$key.mp4',
      audioSource: null,
      videoCandidates: candidates ?? const [],
    ),
  ),
  timeline: PlaybackTimeline(
    kind: kind,
    seekPolicy: seekPolicy,
    duration: kind == PlaybackTimelineKind.live ? null : duration,
  ),
  configuration: PlaybackConfiguration(audioOnly: audioOnly),
);

PlaybackRuntimeLoadResult failedSessionLoad(PlaybackExecutionContext context) =>
    PlaybackRuntimeLoadResult(
      loaded: false,
      output: PlaybackOutputPreparation(
        strategy: PlaybackOutputStrategy.failed,
        evidence: 'source-failed',
        outputEpoch: context.loadId,
      ),
    );

PlaybackRuntimeLoadResult audioSessionLoad(PlaybackExecutionContext context) =>
    PlaybackRuntimeLoadResult(
      loaded: true,
      output: PlaybackOutputPreparation(
        strategy: PlaybackOutputStrategy.noVideo,
        evidence: 'native-track-list-no-video',
        outputEpoch: context.loadId,
        hasVideo: false,
      ),
      capabilities: const PlaybackCapabilities(hasVideo: false, hasAudio: true),
    );

PlaybackRuntimeLoadResult preparedSessionLoad(
  PlaybackExecutionContext context,
  PlaybackPlan plan,
) => PlaybackRuntimeLoadResult(
  loaded: true,
  output: PlaybackOutputPreparation(
    strategy: PlaybackOutputStrategy.prepared,
    evidence: 'fake-explicit-ack',
    outputEpoch: context.loadId,
    hasVideo: true,
  ),
  capabilities: PlaybackCapabilities(
    seekSupport: plan.timeline.seekPolicy == PlaybackSeekPolicy.allowed
        ? PlaybackSeekSupport.supported
        : PlaybackSeekSupport.unknown,
    seekStart: plan.timeline.seekPolicy == PlaybackSeekPolicy.allowed
        ? Duration.zero
        : null,
    seekEnd: plan.timeline.seekPolicy == PlaybackSeekPolicy.allowed
        ? plan.timeline.duration
        : null,
    hasVideo: true,
    hasAudio: false,
  ),
);

Future<void> waitForSessionCondition(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

class FakeSessionRuntime implements PlaybackRuntimePort {
  @override
  final int runtimeId = 51;
  @override
  Duration? position;
  @override
  bool shaderChangeRequiresRendererReset = false;
  final StreamController<PlaybackRuntimeEvent> eventController =
      StreamController<PlaybackRuntimeEvent>.broadcast(sync: true);
  final Completer<void> _released = Completer<void>();
  final loadedKeys = <String>[];
  final loadedPlans = <PlaybackPlan>[];
  final playCalls = <bool>[];
  final seekCalls = <Duration>[];
  Future<PlaybackRuntimeCommandResult> Function(
    Duration,
    PlaybackExecutionContext,
  )?
  onSeek;
  final audioReloadContexts = <PlaybackExecutionContext>[];
  Future<PlaybackRuntimeCommandResult> Function(PlaybackExecutionContext)?
  onReloadAudio;
  final shaderCalls = <List<String>>[];
  final decoderCalls = <String>[];
  final audioOnlyCalls = <bool>[];
  final mutedCalls = <bool>[];
  final volumeCalls = <double>[];
  Future<PlaybackRuntimeCommandResult> Function(bool, PlaybackExecutionContext)?
  onSetMuted;
  final speedCalls = <({double speed, Map<String, String> mediaOptions})>[];
  int _loadIndex = 0;
  int _playIndex = 0;
  Future<PlaybackShutdownResult> Function()? onShutdown;
  Future<PlaybackRuntimeLoadResult> Function(
    PlaybackPlan plan,
    PlaybackExecutionContext context,
    int index,
  )?
  onLoad;
  Future<PlaybackRuntimeCommandResult> Function(
    bool playing,
    PlaybackExecutionContext context,
    int index,
  )?
  onSetPlaying;

  @override
  Stream<PlaybackRuntimeEvent> get events => eventController.stream;

  @override
  Future<void> get released => _released.future;

  void emitActual(int loadId, PlaybackActual actual) {
    position = actual.position;
    eventController.add(
      PlaybackRuntimeStateChanged(
        runtimeId: runtimeId,
        loadId: loadId,
        actual: actual,
      ),
    );
  }

  void completeRelease() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<PlaybackRuntimeLoadResult> load(
    PlaybackPlan plan,
    PlaybackExecutionContext context,
  ) async {
    final index = _loadIndex++;
    loadedKeys.add(plan.contentKey);
    loadedPlans.add(plan);
    final result = onLoad == null
        ? preparedSessionLoad(context, plan)
        : await onLoad!(plan, context, index);
    return result;
  }

  @override
  Future<PlaybackRuntimeCommandResult> setPlaying(
    bool playing,
    PlaybackExecutionContext context,
  ) {
    // 与原生运行时一致：失去归属的命令不会触碰播放器。
    if (!context.isCurrent()) {
      return Future.value(
        const PlaybackRuntimeCommandResult(applied: false),
      );
    }
    final index = _playIndex++;
    if (onSetPlaying != null) return onSetPlaying!(playing, context, index);
    playCalls.add(playing);
    return Future.value(const PlaybackRuntimeCommandResult());
  }

  @override
  Future<PlaybackRuntimeCommandResult> seek(
    Duration target,
    PlaybackExecutionContext context,
  ) async {
    seekCalls.add(target);
    return onSeek?.call(target, context) ??
        const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setPlaybackSpeed(
    double value,
    Map<String, String> mediaOptions,
    PlaybackExecutionContext context,
  ) async {
    speedCalls.add((speed: value, mediaOptions: Map.of(mediaOptions)));
    return const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setVolume(
    double value,
    PlaybackExecutionContext context,
  ) async {
    volumeCalls.add(value);
    return const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setMuted(
    bool value,
    PlaybackExecutionContext context,
  ) async {
    mutedCalls.add(value);
    return onSetMuted?.call(value, context) ??
        const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setAudioOnly(
    bool value,
    PlaybackExecutionContext context,
  ) async {
    audioOnlyCalls.add(value);
    return const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setAudioTrack(
    int? trackId,
    PlaybackExecutionContext context,
  ) async => const PlaybackRuntimeCommandResult();

  @override
  Future<PlaybackRuntimeCommandResult> reloadAudio(
    PlaybackExecutionContext context,
  ) async {
    audioReloadContexts.add(context);
    return onReloadAudio == null
        ? const PlaybackRuntimeCommandResult()
        : onReloadAudio!(context);
  }

  @override
  Future<PlaybackRuntimeCommandResult> setSubtitleTrack(
    PlaybackSubtitleTrack? track,
    PlaybackExecutionContext context,
  ) async => const PlaybackRuntimeCommandResult();

  @override
  Future<PlaybackRuntimeCommandResult> setDecoder(
    PlaybackDecoder decoder,
    PlaybackExecutionContext context,
  ) async {
    decoderCalls.add(decoder.value);
    return const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackRuntimeCommandResult> setShader(
    List<String> shaders,
    PlaybackExecutionContext context,
  ) async {
    shaderCalls.add(List.of(shaders));
    return const PlaybackRuntimeCommandResult();
  }

  @override
  Future<PlaybackShutdownResult> shutdown() async {
    final handler = onShutdown;
    if (handler != null) return handler();
    completeRelease();
    unawaited(eventController.close());
    return const PlaybackShutdownResult.released();
  }
}

class GatedSessionRuntime extends FakeSessionRuntime
    implements PlaybackSeekSubmissionGate {
  final changes = StreamController<void>.broadcast(sync: true);
  bool blocked = true;
  void unblock() {
    blocked = false;
    changes.add(null);
  }

  @override
  bool get seekSubmissionBlocked => blocked;
  @override
  Stream<void> get seekSubmissionChanges => changes.stream;
}

class SamplingSessionRuntime extends FakeSessionRuntime
    implements PlaybackMediaClockSampler {
  void Function()? onSample;
  @override
  void sampleMediaClock() => onSample?.call();
}
