import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;

import 'package:pili_aurora_next/utils/volume_utils.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/features/playback/application/audio_interactions.dart';
import 'package:pili_aurora_next/features/playback/application/audio_media.dart';
import 'package:pili_aurora_next/features/playback/application/audio_playlist.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/http/browser_ua.dart';
import 'package:pili_aurora_next/http/constants.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/audio_normalization.dart';
import 'package:pili_aurora_next/models/video/play/url.dart'
    as http_model
    show Volume;
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart'
    show FavMixin;
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/pages/main_reply/view.dart';
import 'package:pili_aurora_next/pages/sponsor_block/block_mixin.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_repeat.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart'
    show CommandOutcome;
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/audio_handler.dart'
    show MediaNavigation;
import 'package:pili_aurora_next/services/audio_session.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/android/android_helper.dart';
import 'package:pili_aurora_next/utils/connectivity_utils.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;

class AudioController extends GetxController
    with
        GetTickerProviderStateMixin,
        TripleMixin,
        FavMixin,
        BlockConfigMixin,
        BlockMixin,
        AudioNormalizationMixin {
  AudioController({
    Future<Player> Function(PlayerConfiguration)? createPlayer,
    this._initialPlaylist,
  }) : _createPlayer =
           createPlayer ??
           ((configuration) => Player.create(configuration: configuration));

  final Future<Player> Function(PlayerConfiguration) _createPlayer;
  final List<AudioTrack>? _initialPlaylist;

  late Int64 id;
  late Int64 oid;
  late List<Int64> subId;
  late int itemType;
  Int64? extraId;
  late final AudioPlaylistSource from;
  @override
  bool get isUgc => itemType == 1;

  final audioItem = Rxn<AudioTrack>();

  late final _interactions = AudioInteractions(
    target: () => _audioClosed || isClosed
        ? null
        : (oid: oid, type: itemType, parts: subId),
    selectionRevision: () => _playGeneration,
    read: () => audioItem.value,
    publish: _publishTrack,
  );

  late final _playlist = AudioPlaylist(
    anchor: () => (
      id: id,
      oid: oid,
      subIds: List.of(subId),
      itemType: itemType,
      source: from,
      extraId: extraId,
    ),
    prepareAnchor: () {
      final revision = _interactions.statsRevision;
      return (item) => _updateCurrItem(item, requestedAt: revision);
    },
    initialItems: _initialPlaylist,
  );
  ValueListenable<AudioPlaylistSnapshot> get playlistState => _playlist.state;
  int _playGeneration = 0;
  Account? _playAccount;
  bool _playbackReady = false;
  int? _pendingPlayGeneration;
  Future<void>? _playerInitialization;
  NativePlayerCreationFailure? _unreleasedCreation;
  Future<bool>? _mediaOpening;
  bool _audioClosed = false;
  int _speedRevision = 0;
  int _volumeRevision = 0;
  int _seekRevision = 0;
  @override
  Player? player;
  Player? _closingPlayer;
  IndependentAudioLease? _audioLease;

  void _audioEvent(
    String action, {
    Player? target,
    int? generation,
    Object? error,
  }) {
    try {
      Diagnostics.instance.playerLog(
        error == null ? DiagnosticLogLevel.info : DiagnosticLogLevel.warning,
        'audio',
        action,
        details: {
          'audioOwnerId': 'audio.$hashCode',
          if (target != null) 'playerId': 'player.${target.hashCode}',
          'generation': generation ?? _playGeneration,
          'closed': _audioClosed,
          'creationCleanupPending': _unreleasedCreation != null,
          // 原始异常可能包含媒体地址和凭据，只记录类型。
          if (error != null) 'errorType': error.runtimeType.toString(),
        },
      );
    } catch (_) {
      // 诊断失败不改变音频控制和真实释放屏障。
    }
  }

  void _ensureAudioLease() {
    _audioLease ??= audioSessionHandler?.acquireIndependentPlayer(
      setPlaying: (playing) async {
        final target = player;
        if (target == null) return;
        if (playing) {
          await target.play();
        } else {
          await target.pause();
        }
      },
      volume: () => player?.state.volume ?? 0,
      volumeRevision: () => _volumeRevision,
      setVolume: (value) async {
        _volumeRevision++;
        await player?.setVolume(value);
      },
    );
  }

  late int cacheAudioQa;

  late bool isDragging = false;
  final RxInt position = RxInt(0);
  final RxInt duration = RxInt(0);

  late final AnimationController animController;

  List<StreamSubscription>? _subscriptions;

  int? get index => playlistState.value.index;
  List<AudioTrack>? get playlist => playlistState.value.items;

  late double speed = 1.0;

  bool _ownsControl(Player? target, int generation, Account account) =>
      !_audioClosed &&
      !isClosed &&
      identical(player, target) &&
      generation == _playGeneration &&
      identical(account, Accounts.main);

  Player get _readyPlayer => player ?? (throw StateError('音频播放器尚未就绪'));

  void _reportControlFailure(String message, Object error, StackTrace stack) {
    logger
        .scoped('audio')
        .w(message, error: error.runtimeType, stackTrace: stack);
    SmartDialog.showToast(message);
  }

  Future<bool> setSpeed(double value) async {
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    final revision = ++_speedRevision;
    try {
      await _readyPlayer.setRate(value);
      if (!_ownsControl(target, generation, account) ||
          revision != _speedRevision) {
        return false;
      }
      speed = value;
      _updatePlaybackState();
      return true;
    } catch (error, stack) {
      if (_ownsControl(target, generation, account) &&
          revision == _speedRevision) {
        _reportControlFailure('播放速度调整失败，请重试', error, stack);
      }
      return false;
    }
  }

  late final Rx<PlayRepeat> playMode = Pref.audioPlayMode.obs;

  @override
  bool get isLogin => Accounts.main.isLogin;

  Duration? _start;
  VideoDetailController? _videoDetailController;

  double? _lastVolume;
  late final RxDouble desktopVolume = RxDouble(Pref.desktopVolume);

  Timer? _statusTimer;

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer(
      const Duration(milliseconds: 500),
      _updatePlaybackState,
    );
  }

  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  late final volumeDraft = RxDouble(desktopVolume.value);

  Future<void> toggleVolume() async {
    final before = desktopVolume.value;
    final restoring = _lastVolume != null;
    if (await setVolume(_lastVolume ?? 0, clearLastVolme: false)) {
      _lastVolume = restoring ? null : before;
    }
  }

  void previewVolume(double value) {
    volumeDraft.value = roundVolumeRatio(value.clamp(0.0, Pref.maxVolume));
    setVolume(volumeDraft.value);
  }

  Future<bool> setVolume(double volume, {bool clearLastVolme = true}) async {
    volume = roundVolumeRatio(volume.clamp(0.0, Pref.maxVolume));
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    final revision = ++_volumeRevision;
    try {
      await _readyPlayer.setVolume(volumePercent(volume));
      if (!_ownsControl(target, generation, account) ||
          revision != _volumeRevision) {
        return false;
      }
      desktopVolume.value = volume;
      volumeDraft.value = volume;
      if (clearLastVolme) _lastVolume = null;
      return true;
    } catch (error, stack) {
      if (_ownsControl(target, generation, account) &&
          revision == _volumeRevision) {
        volumeDraft.value = desktopVolume.value;
        _reportControlFailure('音量调整失败，请重试', error, stack);
      }
      return false;
    }
  }

  Future<void> commitVolumeChange(double value) async {
    if (await setVolume(value)) await syncVolume();
  }

  Future<void> setPlayerVolumePercent(double value) async {
    if (!await setVolume(value / 100)) return;
    await _saveVolume(
      SettingBoxKey.playerVolume,
      volumePercent(desktopVolume.value),
    );
  }

  Future<void> _saveVolume(String key, double value) async {
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    final revision = _volumeRevision;
    try {
      await GStorage.setting.put(key, value);
    } catch (error, stack) {
      if (_ownsControl(target, generation, account) &&
          revision == _volumeRevision) {
        _reportControlFailure('音量已调整，设置保存失败，请重试', error, stack);
      }
    }
  }

  Future<void> syncVolume([_]) async {
    final volume = desktopVolume.value;
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    final revision = _volumeRevision;
    await _saveVolume(SettingBoxKey.desktopVolume, roundVolumeRatio(volume));
    if (!_ownsControl(target, generation, account) ||
        revision != _volumeRevision) {
      return;
    }
    try {
      final result = await PlPlayerController.instance?.setPlayerVolumePercent(
        volumePercent(volume),
      );
      if (!_ownsControl(target, generation, account) ||
          revision != _volumeRevision) {
        return;
      }
      if (result?.outcome == CommandOutcome.failed) {
        throw result!.failure ?? StateError('视频音量同步失败');
      }
    } catch (error, stack) {
      if (_ownsControl(target, generation, account) &&
          revision == _volumeRevision) {
        _reportControlFailure('音频音量已调整，视频音量同步失败', error, stack);
      }
    }
  }

  @override
  void onInit() {
    super.onInit();
    _ensureAudioLease();
    final args = Get.arguments;
    oid = Int64(args['oid']);
    final id = args['id'];
    this.id = id != null ? Int64(id) : oid;
    subId = (args['subId'] as List<int>?)?.map(Int64.new).toList() ?? [oid];
    itemType = args['itemType'];
    from = args['from'];
    _start = args['start'];
    final int? extraId = args['extraId'];
    if (extraId != null) {
      this.extraId = Int64(extraId);
    }
    if (args['heroTag'] case String heroTag) {
      try {
        _videoDetailController = Get.find<VideoDetailController>(tag: heroTag);
      } catch (_) {}
    }

    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    reloadPlaylist();

    final String? audioUrl = args['audioUrl'];
    final hasAudioUrl = audioUrl != null;
    if (hasAudioUrl) {
      _querySponsorBlock();
      _playAccount = Accounts.main;
      _onOpenMedia(
        audioUrl,
        generation: ++_playGeneration,
        ua: BrowserUa.pc,
        referer: HttpString.baseUrl,
        volume: _videoDetailController?.volume,
      );
    }
    ConnectivityUtils.isWiFi.then((isWiFi) {
      if (isClosed) return;
      cacheAudioQa = isWiFi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular;
      if (!hasAudioUrl) {
        _queryPlayUrl();
      }
    });
    videoPlayerServiceHandler
      ?..onPlay = onPlay
      ..onPause = onPause
      ..onSeek = onSeek;

    if (shutdownTimerService.isActive) {
      shutdownTimerService
        ..onPause = onPause
        ..isPlaying = isPlaying;
    }
  }

  bool isPlaying() {
    return player?.state.playing ?? false;
  }

  Future<void> onPlay() => Future<void>.sync(() {
    final target = _readyPlayer;
    return _audioLease?.setPlaying(true) ?? target.play();
  });

  Future<void> onPause() => Future<void>.sync(() {
    final target = _readyPlayer;
    return _audioLease?.setPlaying(false) ?? target.pause();
  });

  Future<void> onSeek(Duration duration) async {
    final target = _readyPlayer;
    final generation = _playGeneration;
    final account = Accounts.main;
    final revision = ++_seekRevision;
    await target.seek(duration);
    if (!_ownsControl(target, generation, account) ||
        revision != _seekRevision) {
      return;
    }
    position.value = duration.inSeconds;
    _updatePlaybackState(position: duration);
  }

  Future<void> _consumePlaybackControl(
    Future<void> Function() operation,
  ) async {
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    try {
      await operation();
    } catch (error, stack) {
      if (_ownsControl(target, generation, account)) {
        _reportControlFailure('播放操作失败，请重试', error, stack);
      }
    }
  }

  Future<void> playFromUi() => _consumePlaybackControl(onPlay);
  Future<void> pauseFromUi() => _consumePlaybackControl(onPause);

  Future<void> seekFromUi(Duration duration) async {
    final target = player;
    final generation = _playGeneration;
    final account = Accounts.main;
    final operation = onSeek(duration);
    final revision = _seekRevision;
    try {
      await operation;
    } catch (error, stack) {
      if (_ownsControl(target, generation, account) &&
          revision == _seekRevision) {
        position.value = target?.state.position.inSeconds ?? 0;
        _reportControlFailure('进度调整失败，请重试', error, stack);
      }
    }
  }

  void _publishTrack(AudioTrack item) {
    hasLike.value = item.stats.liked;
    coinNum.value = item.stats.viewerCoins;
    hasFav.value = item.stats.favored;
    audioItem.value = item;
    _playlist.confirmStats(item);
  }

  void _updateCurrItem(AudioTrack item, {required int requestedAt}) {
    _interactions.accept(item, requestedAt: requestedAt);
    final handler = videoPlayerServiceHandler;
    if (handler == null || handler.onPlay != onPlay) return;
    try {
      handler.onVideoDetailChange(
        item,
        (subId.firstOrNull ?? oid).toInt(),
        hashCode.toString(),
        navigation: _mediaNavigation,
      );
    } catch (error, stack) {
      logger
          .scoped('audio')
          .w('系统音频信息同步失败', error: error.runtimeType, stackTrace: stack);
    }
  }

  Future<bool> reloadPlaylist() => _playlist.reload();

  void removePlaylistItem(AudioTrack item) => _playlist.remove(item);

  @pragma('vm:notify-debugger-on-exception')
  void _querySponsorBlock() {
    if (isUgc && enableSponsorBlock) {
      try {
        final bvid = IdUtils.av2bv(oid.toInt());
        final cid = subId.first.toInt();
        querySponsorBlock(bvid: bvid, cid: cid);
      } catch (_) {}
    }
  }

  bool _ownsPlayback(int generation) =>
      !_audioClosed &&
      !isClosed &&
      generation == _playGeneration &&
      identical(_playAccount, Accounts.main);

  bool _playbackFailed(Object error, StackTrace stack, int generation) {
    if (_ownsPlayback(generation)) {
      logger
          .scoped('audio')
          .w(
            '音频播放失败',
            error: error.runtimeType,
            stackTrace: stack,
          );
      SmartDialog.showToast('音频播放失败，请重试');
    }
    return false;
  }

  Future<bool> _queryPlayUrl() async {
    final generation = ++_playGeneration;
    _pendingPlayGeneration = generation;
    _playAccount = Accounts.main;
    _playbackReady = false;
    _querySponsorBlock();
    try {
      final res = await AudioMedia.resolve(
        itemType: itemType,
        oid: oid,
        subIds: List.of(subId),
        preferredQuality: () => cacheAudioQa,
      );
      if (!_ownsPlayback(generation)) return false;
      if (res case Success(:final response)) {
        final opened = await _onOpenMedia(
          response.url,
          generation: generation,
          volume: response.volume,
        );
        return opened && _ownsPlayback(generation);
      }
      res.toast();
      return false;
    } catch (error, stack) {
      return _playbackFailed(error, stack, generation);
    } finally {
      if (_pendingPlayGeneration == generation) {
        _pendingPlayGeneration = null;
      }
    }
  }

  Future<bool> _onOpenMedia(
    String url, {
    required int generation,
    String ua = Constants.userAgentApp,
    String? referer,
    http_model.Volume? volume,
  }) {
    _pendingPlayGeneration = generation;
    _ensureAudioLease();
    final lease = _audioLease;
    final intentRevision = lease?.intentRevision;
    final previous = _mediaOpening;
    // 原生 open 不能撤销，串行打开才能保证最后一次选曲最终拥有播放器。
    final operation = () async {
      try {
        await previous;
        if (!_ownsPlayback(generation)) return false;
        if (url.trim().isEmpty) throw const FormatException('音频来源为空');
        // 交接可能仍在等待旧原生句柄销毁，确认后再分配新 Player。
        await _audioLease?.prepare();
        if (!_ownsPlayback(generation)) return false;
        await _initPlayerIfNeeded();
        if (!_ownsPlayback(generation)) return false;
        final currentPlayer = player!
          ..setMediaHeader(
            userAgent: ua,
            // mpv cannot clear referer option
            headers: {'Referer': ?referer},
          );
        _audioEvent(
          'audio.open.begin',
          target: currentPlayer,
          generation: generation,
        );
        try {
          await currentPlayer.open(
            Media(url, start: _start, extras: audioFilterExtras(volume)),
            play: _audioLease == null,
          );
        } catch (error) {
          _audioEvent(
            'audio.open.failed',
            target: currentPlayer,
            generation: generation,
            error: error,
          );
          rethrow;
        }
        // open 的真实回执仍须记录；关闭或切曲后的迟到成功不提交业务状态。
        _audioEvent(
          'audio.open.completed',
          target: currentPlayer,
          generation: generation,
        );
        if (!_ownsPlayback(generation)) return false;
        // 打开期间的显式暂停和拔耳机意图优先于本次自动起播。
        await lease?.setPlaying(
          lease.intentRevision == intentRevision ? true : lease.playingIntent,
        );
        if (!_ownsPlayback(generation)) return false;
        position.value = 0;
        _playbackReady = true;
        _start = null;
        return true;
      } catch (error, stack) {
        return _playbackFailed(error, stack, generation);
      } finally {
        if (_pendingPlayGeneration == generation) {
          _pendingPlayGeneration = null;
        }
      }
    }();
    _mediaOpening = operation;
    return operation;
  }

  PlayerStatus _playerStatus = .paused;
  void _updatePlaybackState({Duration? position, String? debugLabel}) {
    final target = player;
    final handler = videoPlayerServiceHandler;
    if (_audioClosed ||
        isClosed ||
        target == null ||
        handler == null ||
        handler.onPlay != onPlay) {
      return;
    }
    try {
      handler.onUpdateState(
        _playerStatus,
        false,
        false,
        position: position ?? target.state.position,
        speed: speed,
        debugLabel: debugLabel,
      );
    } catch (error, stack) {
      logger
          .scoped('audio')
          .w('系统播放状态同步失败', error: error.runtimeType, stackTrace: stack);
    }
  }

  Future<void> _initPlayerIfNeeded() async {
    if (player != null) return;
    final initialization = _playerInitialization ??= _initializePlayer();
    try {
      await initialization;
    } finally {
      if (identical(_playerInitialization, initialization)) {
        _playerInitialization = null;
      }
    }
  }

  Future<void> _initializePlayer() async {
    // 原生创建可能在分配句柄后失败；清理未确认时拒绝再次分配。
    if (_unreleasedCreation case final failure?) throw failure;
    _ensureAudioLease();
    final generation = _playGeneration;
    _audioEvent('audio.initialize.begin', generation: generation);
    late final Player initializedPlayer;
    try {
      initializedPlayer = await _createPlayer(
        PlayerConfiguration(
          options: {
            if (Platform.isAndroid) 'ao': Pref.audioOutput,
            'volume': PlatformUtils.isDesktop
                ? volumePercent(desktopVolume.value).toStringAsFixed(0)
                : Pref.playerVolume.toString(),
            ...Pref.initBuffer(),
          },
        ),
      );
    } catch (error) {
      if (error is NativePlayerCreationFailure) {
        _unreleasedCreation = error;
        unawaited(
          error.released.then<void>(
            (_) {
              if (identical(_unreleasedCreation, error)) {
                _unreleasedCreation = null;
              }
              _audioEvent(
                'audio.initialize.cleanupReleased',
                generation: generation,
              );
            },
            onError: (Object cleanupError, StackTrace _) {
              _audioEvent(
                'audio.initialize.cleanupFailed',
                generation: generation,
                error: cleanupError,
              );
            },
          ),
        );
      }
      _audioEvent(
        'audio.initialize.failed',
        generation: generation,
        error: error,
      );
      rethrow;
    }
    _audioEvent(
      'audio.initialize.ready',
      target: initializedPlayer,
      generation: generation,
    );
    if (_audioClosed || isClosed) {
      // 交由关闭流程统一销毁，失败必须继续持有音频租约和视频抑制。
      _closingPlayer = initializedPlayer;
      return;
    }
    player = initializedPlayer;
    final stream = initializedPlayer.stream;
    _subscriptions = [
      stream.position.listen((position) {
        if (_audioClosed || isClosed || !identical(player, initializedPlayer)) {
          return;
        }
        if (isDragging) return;
        final seconds = position.inSeconds;
        if (seconds != this.position.value) {
          if (seconds == 0 && _playerStatus.isPlaying) {
            _updatePlaybackState(position: position);
          }
          this.position.value = seconds;
          _videoDetailController?.playedTime = position;
        }
      }),
      stream.duration.listen((duration) {
        if (_audioClosed || isClosed || !identical(player, initializedPlayer)) {
          return;
        }
        this.duration.value = duration.inSeconds;
      }),
      stream.playing.listen((playing) {
        if (_audioClosed || isClosed || !identical(player, initializedPlayer)) {
          return;
        }
        if (playing) {
          animController.forward();
          _playerStatus = .playing;
          _stopStatusTimer();
          _updatePlaybackState();
        } else {
          animController.reverse();
          _playerStatus = .paused;
          _startStatusTimer();
        }
      }),
      stream.buffering.listen((bool buffering) {
        if (_audioClosed || isClosed || !identical(player, initializedPlayer)) {
          return;
        }
        if (!_playerStatus.isCompleted) {
          _stopStatusTimer();
          _updatePlaybackState();
        }
      }),
      stream.completed.listen((completed) {
        if (_audioClosed || isClosed || !identical(player, initializedPlayer)) {
          return;
        }
        _videoDetailController?.playedTime = player!.state.duration;
        if (completed) {
          _playerStatus = .completed;
          _startStatusTimer();
          if (shutdownTimerService.isWaiting) {
            shutdownTimerService.handleWaiting();
          } else {
            switch (playMode.value) {
              case PlayRepeat.pause:
                break;
              case PlayRepeat.listOrder:
                playNext(nextPart: true);
                break;
              case PlayRepeat.singleCycle:
                playFromUi();
                break;
              case PlayRepeat.listCycle:
                if (!playNext(nextPart: true)) {
                  if (index != null && index != 0 && playlist != null) {
                    playIndex(0);
                  } else {
                    playFromUi();
                  }
                }
                break;
              case PlayRepeat.autoPlayRelated:
                break;
            }
          }
        }
      }),
    ];
  }

  Future<void> _showInteractionResult(
    Future<LoadingState<String>?> operation,
  ) async {
    final result = await operation;
    switch (result) {
      case Success(:final response):
        SmartDialog.showToast(response);
      case Error():
        result.toast();
      default:
        break;
    }
  }

  @override
  Future<void> Function(int, bool) get payCoinCallback {
    final isCurrent = _interactions.captureSelection();
    return (coin, withLike) async {
      if (!isCurrent()) {
        if (!_audioClosed && !isClosed) {
          SmartDialog.showToast('曲目或账号已更新，请重新打开投币面板');
        }
        return;
      }
      await onPayCoin(coin, withLike);
    };
  }

  @override
  Future<void> actionLikeVideo() =>
      _showInteractionResult(_interactions.toggleLike());

  @override
  Future<void> actionTriple() => _showInteractionResult(_interactions.triple());

  @override
  int get copyright => audioItem.value?.info.copyright ?? 1;

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) =>
      _showInteractionResult(_interactions.coin(coin, coinWithLike));

  @override
  Object get favoriteOwner => audioItem.value?.info ?? this;

  @override
  Future<void> quickFavorite() =>
      _showInteractionResult(_interactions.quickFavorite());

  @override
  void showFavBottomSheet(BuildContext context, {bool isLongPress = false}) {
    if (_interactions.unavailable() case final error?) {
      error.toast();
      return;
    }
    super.showFavBottomSheet(context, isLongPress: isLongPress);
  }

  void showReply() {
    MainReplyPage.toMainReplyPage(
      oid: oid.toInt(),
      replyType: isUgc ? 1 : 14,
    );
  }

  void actionShareVideo(BuildContext context) {
    final item = audioItem.value?.info;
    final target = item?.target.oid ?? oid;
    final ugc = (item?.target.type ?? itemType) == 1;
    final account = Accounts.main;
    bool current() =>
        context.mounted && !isClosed && identical(account, Accounts.main);
    final audioUrl = ugc
        ? '${HttpString.baseUrl}/video/${IdUtils.av2bv(target.toInt())}'
        : '${HttpString.baseUrl}/audio/au$target';
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          DialogOption(
            child: const Text('复制链接', style: TextStyle(fontSize: 14)),
            onPressed: () {
              if (!current()) return;
              Navigator.of(dialogContext).pop();
              Utils.copyText(audioUrl);
            },
          ),
          DialogOption(
            child: const Text('其它app打开', style: TextStyle(fontSize: 14)),
            onPressed: () {
              if (!current()) return;
              Navigator.of(dialogContext).pop();
              PiliAndroidHelper.openUrl(audioUrl);
            },
          ),
          if (PlatformUtils.isMobile)
            DialogOption(
              child: const Text('分享视频', style: TextStyle(fontSize: 14)),
              onPressed: () {
                if (!current()) return;
                Navigator.of(dialogContext).pop();
                if (item != null) {
                  ShareUtils.shareText(
                    '${item.title} '
                    'UP主: ${item.artistName ?? ''}'
                    ' - $audioUrl',
                  );
                }
              },
            ),
          if (account.isLogin)
            DialogOption(
              child: const Text('分享至动态', style: TextStyle(fontSize: 14)),
              onPressed: () {
                if (!current()) return;
                Navigator.of(dialogContext).pop();
                if (item != null) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => RepostPanel(
                      rid: target.toInt(),
                      dynType: ugc ? 8 : 256,
                      pic: item.cover,
                      title: item.title,
                      uname: item.artistName ?? '',
                    ),
                  );
                }
              },
            ),
          if (ugc && account.isLogin)
            DialogOption(
              child: const Text('分享至消息', style: TextStyle(fontSize: 14)),
              onPressed: () async {
                if (!current()) return;
                Navigator.of(dialogContext).pop();
                if (item != null) {
                  try {
                    await PageUtils.pmShare(
                      context,
                      content: {
                        "id": target.toString(),
                        "title": item.title,
                        "headline": item.title,
                        "source": 5,
                        "thumb": item.cover,
                        "author": item.artistName ?? '',
                        "author_id": item.artistId.toString(),
                      },
                    );
                  } catch (error, stack) {
                    logger
                        .scoped('audio')
                        .w(
                          '音频消息分享失败',
                          error: error.runtimeType,
                          stackTrace: stack,
                        );
                    if (current()) SmartDialog.showToast('分享失败，请重试');
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> playOrPause() => _consumePlaybackControl(() {
    if (_audioLease case final lease?) {
      return lease.playingIntent ? onPause() : onPlay();
    }
    return _readyPlayer.playOrPause();
  });

  MediaNavigation get _mediaNavigation {
    final account = Accounts.main;
    return MediaNavigation(
      isCurrent: () =>
          !_audioClosed &&
          !isClosed &&
          player != null &&
          identical(account, Accounts.main) &&
          videoPlayerServiceHandler?.onPlay == onPlay,
      next: () => _skipPlaylist(1),
      previous: () => _skipPlaylist(-1),
    );
  }

  Future<void>? _playAdjacent(int offset) {
    if (_audioClosed ||
        isClosed ||
        index == null ||
        playlist == null ||
        player == null) {
      return null;
    }
    final next = index! + offset;
    if (next < 0 || next >= playlist!.length) return null;
    if (offset > 0 &&
        next == playlist!.length - 1 &&
        playlistState.value.hasNext) {
      loadNext();
    }
    return playIndex(next);
  }

  Future<bool> _skipPlaylist(int offset) async {
    final operation = _playAdjacent(offset);
    if (operation == null) return false;
    await operation;
    return true;
  }

  bool playPrev() => _playAdjacent(-1) != null;

  bool playNext({bool nextPart = false}) {
    if (nextPart) {
      if (audioItem.value?.info case AudioTrackInfo(:final parts)) {
        if (parts.length > 1) {
          final subId = this.subId.firstOrNull;
          final nextIndex = parts.indexWhere((e) => e.subId == subId) + 1;
          if (nextIndex != 0 && nextIndex < parts.length) {
            final nextPart = parts[nextIndex];
            _start = null;
            oid = nextPart.oid;
            this.subId = [nextPart.subId];
            final operation = _queryPlayUrl();
            final generation = _playGeneration;
            operation.then((res) {
              if (res && _ownsPlayback(generation)) {
                _videoDetailController = null;
              }
            });
            return true;
          }
        }
      }
    }
    return _playAdjacent(1) != null;
  }

  Future<void> selectPlaylistItem(AudioTrack item, {List<Int64>? subId}) {
    final selected = _playlist.indexOf(item);
    if (selected == null) return Future.value();
    return playIndex(selected, subId: subId);
  }

  Future<void> playIndex(int index, {List<Int64>? subId}) async {
    final items = playlist;
    if (_audioClosed ||
        isClosed ||
        items == null ||
        index < 0 ||
        index >= items.length) {
      return;
    }
    final audioItem = items[index];
    final item = audioItem.info.target;
    final targetSubIds =
        subId ??
        (item.parts.isNotEmpty
            ? item.parts
            : [
                if (audioItem.info.parts.firstOrNull case final part?)
                  part.subId,
              ]);
    if (index == this.index &&
        item.oid == oid &&
        item.type == itemType &&
        listEquals(targetSubIds, this.subId) &&
        _ownsPlayback(_playGeneration) &&
        (_playbackReady || _pendingPlayGeneration == _playGeneration)) {
      return;
    }
    _start = null;
    _playlist.select(index);
    oid = item.oid;
    this.subId = List.of(targetSubIds);
    itemType = item.type;
    final statsRevision = _interactions.statsRevision;
    final operation = _queryPlayUrl();
    final generation = _playGeneration;
    if (await operation && _ownsPlayback(generation)) {
      _videoDetailController = null;
      _updateCurrItem(audioItem, requestedAt: statsRevision);
    }
  }

  @override
  (Object, int) get getFavRidType => (oid, isUgc ? 2 : 12);

  @override
  void updateFavCount(int count) => _interactions.confirmFavorite(count > 0);

  Future<bool> loadPrev() => _playlist.loadPrevious();

  Future<bool> loadNext() => _playlist.loadNext();

  Future<bool> retryPlaylistPage() => _playlist.retryPage();

  Future<bool> onChangeOrder(AudioPlaylistOrder value) =>
      _playlist.changeOrder(value);

  @override
  BlockConfigMixin get blockConfig => this;

  @override
  Future<void> applyBlockMute(bool muted) async {
    player?.setProperty('mute', muted ? 'yes' : 'no');
  }

  @override
  int get currPosInMilliseconds => player?.state.position.inMilliseconds ?? 0;

  @override
  int? get timeLength => player?.state.duration.inMilliseconds ?? 0;

  @override
  Future<void>? seekTo(Duration duration, {required bool isSeek}) =>
      onSeek(duration);

  @override
  bool get autoPlay => true;

  @override
  bool get preInitPlayer => true;

  void _releaseAudioResource(FutureOr<void> Function() release) {
    unawaited(
      Future<void>.sync(release).catchError((Object error, StackTrace stack) {
        logger
            .scoped('audio')
            .w('音频资源释放失败', error: error.runtimeType, stackTrace: stack);
      }),
    );
  }

  @override
  void onClose() {
    _audioClosed = true;
    _audioEvent('audio.shutdown.requested', target: player ?? _closingPlayer);
    _playlist.dispose();
    _playGeneration++;
    _stopStatusTimer();
    final ownsTimerPause = shutdownTimerService.onPause == onPause;
    final ownsTimerPlaying = shutdownTimerService.isPlaying == isPlaying;
    if (ownsTimerPause) shutdownTimerService.onPause = null;
    if (ownsTimerPlaying) shutdownTimerService.isPlaying = null;
    if ((ownsTimerPause || ownsTimerPlaying) &&
        shutdownTimerService.onPause == null &&
        shutdownTimerService.isPlaying == null) {
      shutdownTimerService.reset();
    }
    final handler = videoPlayerServiceHandler;
    if (handler != null) {
      final ownsPlay = handler.onPlay == onPlay;
      final ownsPause = handler.onPause == onPause;
      final ownsSeek = handler.onSeek == onSeek;
      if (ownsPlay) handler.onPlay = null;
      if (ownsPause) handler.onPause = null;
      if (ownsSeek) handler.onSeek = null;
      _releaseAudioResource(() {
        handler.onVideoDetailDispose(hashCode.toString());
        if (ownsPlay || ownsPause || ownsSeek) handler.clearIfNeeded();
      });
    }
    for (final subscription in _subscriptions ?? <StreamSubscription>[]) {
      _releaseAudioResource(subscription.cancel);
    }
    _subscriptions = null;
    final target = player;
    player = null;
    final lease = _audioLease;
    _audioLease = null;
    _releaseAudioResource(() {
      Future<void> release() async {
        // 等初始化和不可撤销的 open 真正退出后再销毁，最后交还视频抑制。
        try {
          await _playerInitialization;
        } catch (_) {
          // 创建失败已交付；可能已分配的原生句柄仍须单独等待清理。
        }
        await _mediaOpening;
        if (_unreleasedCreation case final failure?) {
          _audioEvent('audio.shutdown.waitingForCreation');
          try {
            await failure.released;
          } catch (error) {
            _audioEvent('audio.shutdown.failed', error: error);
            rethrow;
          }
        }
        final releasing = target ?? _closingPlayer;
        if (releasing != null) {
          _audioEvent('audio.shutdown.disposing', target: releasing);
          try {
            await releasing.dispose();
          } catch (error) {
            _audioEvent(
              'audio.shutdown.failed',
              target: releasing,
              error: error,
            );
            rethrow;
          }
        }
        _audioEvent('audio.shutdown.released', target: releasing);
        _closingPlayer = null;
      }

      // 立即登记关闭，后续音频接管必须等待上述真实释放屏障。
      return lease?.close(release) ?? release();
    });
    animController.dispose();
    super.onClose();
  }
}
