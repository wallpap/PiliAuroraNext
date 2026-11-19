import 'dart:async' as async;
import 'dart:async' show Timer, StreamController, StreamSubscription, unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:pili_aurora_next/common/widgets/dialog/report.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/controller.dart';
import 'package:pili_aurora_next/features/playback/application/live_chat_connection.dart';
import 'package:pili_aurora_next/features/playback/application/live_chat_queries.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_interactions.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_queries.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_source.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/super_chat_type.dart';
import 'package:pili_aurora_next/models/common/video/live_quality.dart';
import 'package:pili_aurora_next/models/model_owner.dart';
import 'package:pili_aurora_next/models/remote/live/live_danmaku/danmaku_msg.dart';
import 'package:pili_aurora_next/models/remote/live/live_danmaku/live_emote.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_info/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_medal_wall/uinfo_medal.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_info_h5/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/stream.dart';
import 'package:pili_aurora_next/models/remote/live/live_superchat/item.dart';
import 'package:pili_aurora_next/pages/common/publish/publish_route.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/pages/danmaku/live_queue.dart';
import 'package:pili_aurora_next/pages/live_room/chat_buffer.dart';
import 'package:pili_aurora_next/pages/live_room/send_danmaku/view.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_source.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_session.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/danmaku_options.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/services/live_stream/live.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/android/bindings.g.dart';
import 'package:pili_aurora_next/features/danmaku/presentation/danmaku_position.dart';
import 'package:pili_aurora_next/utils/color_utils.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/services/settings/display_preferences.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kReleaseMode, listEquals, protected;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LiveRoomController {
  LiveRoomController(this.heroTag, this.roomId);
  final String heroTag;

  int roomId;
  bool _closed = false;
  bool get isClosed => _closed;
  int? ruid;
  final _liveDanmakuMessages =
      StreamController<LiveDanmakuMessage<DanmakuExtra>>.broadcast(sync: true);
  late final async.Stream<LiveDanmakuMessage<DanmakuExtra>>
  liveDanmakuMessages = _liveDanmakuMessages.stream;
  int _liveMessageSequence = 0;
  final plPlayerController = PlPlayerController.getInstance(
    isLive: true,
  );

  late final PlaybackOwner playbackOwner;
  ShutdownPlaybackBinding? _shutdownBinding;

  void _bindShutdownTimer() {
    if (!playbackOwner.isActive || _shutdownBinding?.isBound == true) return;
    _shutdownBinding = shutdownTimerService.bindPlayer(
      pause: plPlayerController.pause,
      isPlaying: () =>
          playbackOwner.isActive && plPlayerController.playerStatus.isPlaying,
      supportsCompletion: false,
    );
  }

  NetworkSource? _networkSource;
  PlaybackPlan? _playbackPlan;
  PlaybackInhibitorToken? _routeInhibitor;
  int _sourceGeneration = 0;

  final isLoaded = false.obs;
  final roomInfoH5 = Rxn<RoomInfoH5Data>();
  final _roomQueries = LiveRoomQueries();

  final liveTime = Rxn<int>();
  Timer? liveTimeTimer;

  void startLiveTimer() {
    if (liveTime.value != null) {
      liveTimeTimer ??= Timer.periodic(
        const Duration(minutes: 5),
        (_) => liveTime.refresh(),
      );
    }
  }

  void cancelLiveTimer() {
    liveTimeTimer?.cancel();
    liveTimeTimer = null;
  }

  Widget get timeWidget => Obx(() {
    final liveTime = this.liveTime.value;
    String text = '';
    if (liveTime != null) {
      final duration = DurationUtils.formatDurationBetween(
        liveTime * 1000,
        DateTime.now().millisecondsSinceEpoch,
      );
      text += duration.isEmpty ? '刚刚开播' : '开播$duration';
    }
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white,
      ),
    );
  });

  // dm
  LiveDmInfoData? get dmInfo => _chatConnection.token;
  List<RichTextItem>? savedDanmaku;
  final chatBuffer = LiveChatBuffer<dynamic>();
  final messages = Rx<List<LiveChatMessage<dynamic>>>(const []);
  final unreadMessages = (0, 0).obs;
  final historyTruncated = false.obs;
  int _publishedMessageRevision = 0;
  Timer? _messageRefreshTimer;
  bool get shouldRefresh => _publishedMessageRevision != chatBuffer.revision;
  late final fsSC = Rxn<SuperChatItem>();
  late final RxList<SuperChatItem> superChatMsg = <SuperChatItem>[].obs;
  final disableAutoScroll = false.obs;
  bool _autoScroll = true;
  bool get autoScroll => _autoScroll;
  set autoScroll(bool value) {
    _autoScroll = value;
    if (!value) chatBuffer.pause();
  }

  bool get _followingLatest => autoScroll && !disableAutoScroll.value;
  late final _chatConnection = LiveChatConnection(
    currentRoom: () => isClosed ? null : roomId,
    loadToken: fetchLiveMessageToken,
    createStream: createLiveMessageStream,
    onMessage: _danmakuListener,
    onFailure: SmartDialog.showToast,
  );

  List<String> _keywordList = const [];
  Set<int> _shieldUids = const {};

  late final ScrollController scrollController;
  late final RxInt pageIndex = 0.obs;
  PageController? pageController;

  int? currentQn = PlatformUtils.isMobile ? null : Pref.liveQuality;
  final currentQnDesc = ''.obs;
  final RxBool isPortrait = false.obs;
  late List<({int code, String desc})> acceptQnList = [];

  bool get isLogin => AccountScope.signedIn;
  int get mid => AccountScope.capture().account.mid;

  String? videoUrl;
  late bool isFullScreen = false;

  final superChatType = Pref.superChatType;
  late final showSuperChat = superChatType != SuperChatType.disable;

  final headerKey = GlobalKey<TimeBatteryMixin>();

  final RxString title = ''.obs;

  final RxnString onlineCount = RxnString();

  final RxnString watchedShow = RxnString();
  Widget get watchedWidget => Obx(() {
    if (watchedShow.value case final watchedShow?) {
      return Text(
        watchedShow,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white,
        ),
      );
    }
    return const SizedBox.shrink();
  });

  void _publishMessages() {
    if (shouldRefresh) {
      messages.value = chatBuffer.history;
      _publishedMessageRevision = chatBuffer.revision;
    }
    unreadMessages.value = (chatBuffer.pendingCount, chatBuffer.droppedPending);
    historyTruncated.value = chatBuffer.historyTruncated;
  }

  void _scheduleMessageRefresh() {
    if (_messageRefreshTimer != null) return;
    _messageRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _messageRefreshTimer = null;
      _publishMessages();
    });
  }

  void _flushMessageRefresh() {
    _messageRefreshTimer?.cancel();
    _messageRefreshTimer = null;
    _publishMessages();
  }

  StreamSubscription? _sizeSub;

  void _onSizeChanged((int, int) value) {
    final isVertical = value.$2 > value.$1;
    isPortrait.value = isVertical;
    plPlayerController.isVertical = isVertical;
  }

  void _startSizeSub() {
    if (isPortrait.value) return;
    _stopSizeSub();
    _sizeSub = plPlayerController.videoPlayerController?.stream.size.listen(
      _onSizeChanged,
    );
  }

  void _stopSizeSub() {
    _sizeSub?.cancel();
    _sizeSub = null;
  }

  void open() {
    playbackOwner = plPlayerController.attachPlaybackOwner();
    _bindShutdownTimer();
    scrollController = ScrollController()..addListener(listener);
    queryLiveUrl(autoFullScreenFlag: true);
    queryLiveInfoH5();
    unawaited(LiveRoomQueries.recordEntry(roomId));
    if (showSuperChat) {
      pageController = PageController();
    }
  }

  Future<void> retryPlayback() async {
    if (plPlayerController.processing) return;
    await queryLiveUrl(startPolicy: PlaybackStartPolicy.preserve);
  }

  Future<void> queryLiveUrl({
    bool autoFullScreenFlag = false,
    PlaybackStartPolicy? startPolicy,
  }) async {
    await _loadLiveQuery(
      autoFullScreenFlag: autoFullScreenFlag,
      startPolicy: startPolicy,
    );
  }

  Future<LoadResult> _loadLiveQuery({
    bool autoFullScreenFlag = false,
    PlaybackStartPolicy? startPolicy,
    int? requestedQn,
  }) async {
    if (isClosed) return const LoadResult.closed();
    if (!playbackOwner.isActive) return const LoadResult.inactive();
    final generation = ++_sourceGeneration;
    final ownsPlayback = playbackOwner.guard();
    final accountOwner = AccountScope.captureHeartbeat();
    final account = accountOwner.account;
    final requestedRoomId = roomId;
    bool current() =>
        !isClosed &&
        ownsPlayback() &&
        generation == _sourceGeneration &&
        roomId == requestedRoomId &&
        accountOwner.isCurrent;
    final contentKey = 'live:$requestedRoomId';
    final start =
        startPolicy ??
        (plPlayerController.currentPlaybackContentKey == contentKey
            ? PlaybackStartPolicy.preserve
            : plPlayerController.wantsToPlay || _networkSource == null
            ? PlaybackStartPolicy.play
            : PlaybackStartPolicy.pause);
    try {
      final configuration = plPlayerController.capturePlaybackConfiguration(
        live: true,
        audioOnly: plPlayerController.onlyPlayAudio.value,
      );
      LiveRoomSource? selection;
      PlaybackPlan? plan;
      RoomPlayInfoData? info;
      final result = await playbackOwner.query(
        (query) async {
          try {
            return await _queryLiveUrl(
              requestedRoomId,
              account,
              configuration,
              query,
              requestedQn ?? currentQn,
              current,
              (selected, prepared, response) {
                selection = selected;
                plan = prepared;
                info = response;
              },
              showFailureDialog: requestedQn == null,
            );
          } catch (error, stackTrace) {
            _sourceFailure('直播地址准备失败', error, stackTrace);
            if (current() && requestedQn == null) {
              _showDialog('直播地址准备失败，请重试');
            }
            throw const FormatException('直播地址准备失败');
          }
        },
        start: start,
        shouldLoad: current,
      );
      if (!current()) return const LoadResult.superseded();
      if (result.outcome == LoadOutcome.ready &&
          selection != null &&
          plan != null &&
          info != null) {
        final firstLoad = !isLoaded.value;
        _confirmLiveSource(selection!, plan!);
        ruid = info!.uid;
        _updateRoomId(info!.roomId ?? requestedRoomId);
        liveTime.value = info!.liveTime;
        startLiveTimer();
        isPortrait.value = info!.isPortrait ?? false;
        isLoaded.value = true;
        _startSizeSub();
        plPlayerController.onPlaybackQueryReady(
          autoFullScreenFlag: autoFullScreenFlag,
        );
        if (firstLoad && account.isLogin) unawaited(_fetchBlockRules());
      } else if (requestedQn != null && result.outcome == LoadOutcome.failed) {
        SmartDialog.showToast('直播画质切换失败，请重试');
      }
      return result;
    } catch (error, stackTrace) {
      final result = _sourceFailure('直播地址准备失败', error, stackTrace);
      if (current()) SmartDialog.showToast('直播地址准备失败，请重试');
      return current() ? result : const LoadResult.superseded();
    }
  }

  Future<PlaybackPlan?> _queryLiveUrl(
    int requestedRoomId,
    Account account,
    PlaybackConfiguration configuration,
    PlaybackQuery query,
    int? qn,
    bool Function() ownsSource,
    void Function(LiveRoomSource, PlaybackPlan, RoomPlayInfoData) prepared, {
    required bool showFailureDialog,
  }) async {
    bool isCurrent() => ownsSource() && query.isCurrent;
    final res = await LiveRoomQueries.playback(
      room: requestedRoomId,
      account: account,
      quality: qn,
      audioOnly: configuration.audioOnly,
      registerCancel: query.registerCancel,
      current: isCurrent,
    );
    if (res == null || !isCurrent()) return null;
    if (res case Success(:final response)) {
      if (response.liveStatus != 1) {
        if (showFailureDialog) _showDialog('当前直播间未开播');
        return null;
      }
      final playurl = response.playurlInfo?.playurl;
      if (playurl == null) {
        if (showFailureDialog) _showDialog('无法获取播放地址');
        return null;
      }
      final selection = LiveRoomSource.preferred(playurl.stream);
      if (!isCurrent()) return null;
      final plan = plPlayerController.createPlaybackPlan(
        contentKey: 'live:${response.roomId ?? requestedRoomId}',
        source: selection.source,
        configuration: configuration,
        timelineKind: PlaybackTimelineKind.live,
        seekPolicy: PlaybackSeekPolicy.disabled,
      );
      plPlayerController.preparePlaybackPlan(
        owner: playbackOwner,
        plan: plan,
        live: true,
        isVertical: response.isPortrait ?? false,
      );
      prepared(selection, plan, response);
      return plan;
    } else {
      if (showFailureDialog) _showDialog(res.toString());
      return null;
    }
  }

  List<Stream> stream = const [];
  int streamIndex = 0;
  int formatIndex = 0;
  int codecIndex = 0;
  int liveUrlIndex = 0;

  Future<LoadResult> initLiveUrl({
    int streamIndex = 0,
    int formatIndex = 0,
    int codecIndex = 0,
    int liveUrlIndex = 0,
    bool autoFullScreenFlag = false,
    bool? autoplay,
    bool Function()? isCurrent,
  }) async {
    if (isClosed) return const LoadResult.closed();
    if (!playbackOwner.isActive) return const LoadResult.inactive();
    if (!(isCurrent?.call() ?? true)) return const LoadResult.superseded();
    if (isCurrent == null) playbackOwner.invalidateRequests();
    final generation = ++_sourceGeneration;
    final ownsPlayback = playbackOwner.guard();
    final accountOwner = AccountScope.captureHeartbeat();
    final requestedRoomId = roomId;
    final streams = stream;
    bool current() =>
        !isClosed &&
        ownsPlayback() &&
        generation == _sourceGeneration &&
        roomId == requestedRoomId &&
        accountOwner.isCurrent &&
        identical(streams, stream) &&
        (isCurrent?.call() ?? true);
    try {
      final selection = LiveRoomSource.select(
        streams,
        streamIndex: streamIndex,
        formatIndex: formatIndex,
        codecIndex: codecIndex,
        liveUrlIndex: liveUrlIndex,
      );
      final configuration = plPlayerController.capturePlaybackConfiguration(
        live: true,
        source: selection.source,
        audioOnly: plPlayerController.onlyPlayAudio.value,
      );
      final plan = plPlayerController.createPlaybackPlan(
        contentKey: 'live:$requestedRoomId',
        source: selection.source,
        configuration: configuration,
        timelineKind: PlaybackTimelineKind.live,
        seekPolicy: PlaybackSeekPolicy.disabled,
      );
      final result = await plPlayerController.loadPlaybackPlan(
        owner: playbackOwner,
        plan: plan,
        start: autoplay == null
            ? PlaybackStartPolicy.preserve
            : autoplay
            ? PlaybackStartPolicy.play
            : PlaybackStartPolicy.pause,
        live: true,
        isVertical: isPortrait.value,
        autoFullScreenFlag: autoFullScreenFlag,
      );
      if (!current()) return const LoadResult.superseded();
      if (result.outcome == LoadOutcome.ready) {
        _confirmLiveSource(selection, plan);
        _startSizeSub();
        try {
          await selection.remember();
        } catch (error, stackTrace) {
          _sourceFailure('直播线路偏好保存失败', error, stackTrace);
          if (current()) SmartDialog.showToast('线路已切换，但偏好保存失败');
        }
      } else if (result.outcome == LoadOutcome.failed) {
        SmartDialog.showToast('直播线路切换失败，请重试');
      }
      return result;
    } catch (error, stackTrace) {
      final result = _sourceFailure('直播线路准备失败', error, stackTrace);
      if (!current()) return const LoadResult.superseded();
      SmartDialog.showToast('直播线路准备失败，请重试');
      return result;
    }
  }

  void _confirmLiveSource(LiveRoomSource selection, PlaybackPlan plan) {
    stream = selection.streams;
    streamIndex = selection.streamIndex;
    formatIndex = selection.formatIndex;
    codecIndex = selection.codecIndex;
    liveUrlIndex = selection.liveUrlIndex;
    final item = selection.codec;
    // 以服务端返回的码率为准
    currentQn = item.currentQn;
    acceptQnList = item.acceptQn.map((e) {
      return (
        code: e,
        desc: LiveQuality.fromCode(e)?.desc ?? e.toString(),
      );
    }).toList();
    currentQnDesc.value =
        LiveQuality.fromCode(currentQn)?.desc ?? currentQn.toString();
    _networkSource = selection.source;
    videoUrl = selection.source.videoSource;
    _playbackPlan = plan;
  }

  LoadResult _sourceFailure(String operation, Object error, StackTrace stack) {
    // 原生错误可能包含带签名的地址，诊断只保留类型与调用栈。
    logger.w(operation, error: error.runtimeType, stackTrace: stack);
    return LoadResult.failed(
      PlaybackFailure(
        category: PlaybackFailureCategory.source,
        operation: operation,
        stage: PlaybackStage.resolving,
        recoverable: true,
        cause: operation,
      ),
    );
  }

  bool _matchesConfirmedLivePlan(PlaybackPlan? plan) {
    final confirmed = _playbackPlan;
    return plan != null &&
        confirmed != null &&
        plan.contentKey == confirmed.contentKey &&
        listEquals(
          plan.source.videoCandidates,
          confirmed.source.videoCandidates,
        ) &&
        listEquals(
          plan.source.audioCandidates,
          confirmed.source.audioCandidates,
        );
  }

  void holdPlaybackForRoute() {
    _sourceGeneration++;
    playbackOwner.invalidateRequests();
    final snapshot = plPlayerController.currentPlaybackSnapshot;
    final plan = plPlayerController.currentPlaybackPlan;
    final position = snapshot.actual.position;
    if (plan != null && _matchesConfirmedLivePlan(plan) && position != null) {
      _playbackPlan = PlaybackPlan(
        contentKey: plan.contentKey,
        source: plan.source,
        timeline: plan.timeline,
        configuration: snapshot.configuration.desired,
        startPosition: position,
        reloadPosition: position,
        metadata: plan.metadata,
      );
    }
    _routeInhibitor ??= playbackOwner.acquireInhibitor(
      PlaybackInhibitorSource.system,
    );
  }

  Future<void> restorePlaybackAfterRoute() async {
    plPlayerController.activatePlaybackOwner(playbackOwner);
    _bindShutdownTimer();
    final plan = _playbackPlan;
    final token = _routeInhibitor;
    if (plan != null && !isClosed) {
      final result = await loadPlaybackPlanForRoute(
        plan,
        start: PlaybackStartPolicy.preserve,
      );
      if (result.outcome == LoadOutcome.ready && !isClosed) {
        isLoaded.value = true;
      }
    } else if (plan == null && !isClosed) {
      await queryLiveUrl(startPolicy: PlaybackStartPolicy.preserve);
    }
    if (token != null) {
      _routeInhibitor = null;
      await playbackOwner.releaseInhibitor(token);
    }
    if (!isClosed && plPlayerController.playerStatus.isPlaying) {
      await startLiveMsg();
    }
  }

  Future<LoadResult> loadPlaybackPlanForRoute(
    PlaybackPlan plan, {
    required PlaybackStartPolicy start,
  }) => plPlayerController.loadPlaybackPlan(
    owner: playbackOwner,
    plan: plan,
    start: start,
    live: true,
    isVertical: isPortrait.value,
  );

  Future<void> queryLiveInfoH5() async {
    final ownsPlayback = playbackOwner.guard();
    if (isClosed || !ownsPlayback()) return;
    final target = roomId;
    bool current() => !isClosed && ownsPlayback() && target == roomId;
    final res = await _roomQueries.details(target, current: current);
    if (res == null || !current()) return;
    if (res case Success(:final response)) {
      roomInfoH5.value = response;
      title.value = response.roomInfo?.title ?? '';
      watchedShow.value = response.watchedShow?.textLarge;
      videoPlayerServiceHandler?.onVideoDetailChange(response, roomId, heroTag);
    } else {
      res.toast();
    }
  }

  void _showDialog(String title) {
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '关闭',
              style: TextStyle(color: ThemeUtils.theme.colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              if (plPlayerController.isDesktopPip) {
                plPlayerController.exitDesktopPip();
              }
              Get
                ..back()
                ..back();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void scrollToBottom() {
    ActionThrottle.run(
      'liveDm:$heroTag',
      const Duration(milliseconds: 500),
      () => WidgetsBinding.instance.addPostFrameCallback(_scrollToBottom),
    );
  }

  void _scrollToBottom([_]) {
    if (!isClosed && _followingLatest && scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linearToEaseOut,
      );
    }
  }

  void handleJumpToBottom() {
    disableAutoScroll.value = false;
    chatBuffer.resume();
    _flushMessageRefresh();
    _jumpToBottom();
    WidgetsBinding.instance.addPostFrameCallback(_jumpToBottom);
  }

  void _jumpToBottom([_]) {
    if (!isClosed && _followingLatest && scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
  }

  void _updateRoomId(int value) {
    if (roomId == value) return;
    final reconnect = _chatConnection.wantsConnection;
    _chatConnection.close(discardToken: true);
    roomId = value;
    if (roomInfoH5.value == null) unawaited(queryLiveInfoH5());
    if (reconnect) unawaited(startLiveMsg());
  }

  bool _isCurrentMessageTask(int generation, int targetRoomId) =>
      _chatConnection.isCurrent(generation, targetRoomId);

  void closeLiveMsg() => _chatConnection.close();

  @pragma('vm:notify-debugger-on-exception')
  Future<void> prefetch() => _prefetchFor(_chatConnection.generation, roomId);

  @protected
  Future<LoadingState<List<DanmakuMsg>?>> fetchLiveMessageHistory(int roomId) =>
      LiveChatQueries.history(roomId);

  Future<void> _prefetchFor(int generation, int targetRoomId) async {
    if (!_isCurrentMessageTask(generation, targetRoomId)) return;
    final LoadingState<List<DanmakuMsg>?> res;
    try {
      res = await fetchLiveMessageHistory(targetRoomId);
    } catch (_) {
      return;
    }
    if (!_isCurrentMessageTask(generation, targetRoomId)) return;
    if (res case Success(:final response)) {
      if (response != null && response.isNotEmpty) {
        for (final item in response) {
          if (!_isCurrentMessageTask(generation, targetRoomId)) return;
          if (!isBlocked(item.text, item.extra.mid)) addDm(item);
        }
        _flushMessageRefresh();
        scrollToBottom();
      }
    } else {
      if (kDebugMode) {
        Utils.reportError(res.toString());
      }
    }
  }

  Future<void> _getSuperChatMsgFor(int generation, int targetRoomId) async {
    if (!_isCurrentMessageTask(generation, targetRoomId)) return;
    try {
      final list = await LiveChatQueries.superChat(targetRoomId);
      if (!_isCurrentMessageTask(generation, targetRoomId)) return;
      if (list.isNotEmpty) {
        superChatMsg.addAll(list);
      }
    } catch (_) {
      return;
    }
  }

  void clearSC() {
    superChatMsg.removeWhere((e) => e.expired);
  }

  Future<void> _fetchBlockRules() async {
    final target = roomId;
    final accountOwner = AccountScope.capture();
    final res = await LiveChatQueries.blockRules(target, accountOwner.account);
    if (isClosed || target != roomId || !accountOwner.isCurrent) {
      return;
    }
    if (res case Success(:final response?)) {
      if (response.keywordList case final keywordList?) {
        _keywordList = keywordList;
      }
      if (response.shieldUserList case final shieldUserList?) {
        _shieldUids = shieldUserList.map((e) => e.uid).toSet();
      }
    }
  }

  void updateBlockRules(List<String> keywords, Set<int> uids) {
    _keywordList = keywords;
    _shieldUids = uids;
  }

  bool isBlocked(String text, Object uid) {
    return _shieldUids.contains(uid) || _keywordList.any(text.contains);
  }

  Future<void> startLiveMsg() => _chatConnection.open(
    room: roomId,
    prefetch: chatBuffer.historyCount == 0 && chatBuffer.pendingCount == 0
        ? (generation, targetRoomId) {
            unawaited(_prefetchFor(generation, targetRoomId));
            if (showSuperChat) {
              unawaited(_getSuperChatMsgFor(generation, targetRoomId));
            }
          }
        : null,
  );

  @protected
  Future<LoadingState<LiveDmInfoData>> fetchLiveMessageToken(int roomId) =>
      LiveChatQueries.token(roomId);

  @protected
  LiveMessageStream createLiveMessageStream({
    required LiveDmInfoData info,
    required int roomId,
  }) => LiveMessageStream(
    streamToken: info.token,
    roomId: roomId,
    uid: AccountScope.captureHeartbeat().account.mid,
    servers: info.hostList
        .map((host) => 'wss://${host.host}:${host.wssPort}/sub')
        .toList(),
  );

  void listener() {
    final userScrollDirection = scrollController.position.userScrollDirection;
    if (userScrollDirection == .reverse) {
      disableAutoScroll.value = true;
      chatBuffer.pause();
    } else if (userScrollDirection == .forward) {
      final pos = scrollController.position;
      if (pos.pixels <= 100 && disableAutoScroll.value) {
        disableAutoScroll.value = false;
        refreshMsgIfNeeded();
      }
    }
  }

  void refreshMsgIfNeeded() {
    if (isClosed) return;
    if (_followingLatest) chatBuffer.resume();
    _flushMessageRefresh();
    if (_followingLatest) scrollToBottom();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _shutdownBinding?.dispose();
    plPlayerController.closePlaybackOwner(playbackOwner);
    _stopSizeSub();
    closeLiveMsg();
    _likes.dispose();
    _roomQueries.dispose();
    cancelLiveTimer();
    _messageRefreshTimer?.cancel();
    _messageRefreshTimer = null;
    ActionThrottle.cancel('liveDm:$heroTag');
    savedDanmaku?.clear();
    savedDanmaku = null;
    chatBuffer.clear();
    messages.value = const [];
    if (showSuperChat) {
      superChatMsg.clear();
      fsSC.value = null;
    }
    scrollController
      ..removeListener(listener)
      ..dispose();
    pageController?.dispose();
    unawaited(_liveDanmakuMessages.close());
  }

  // 修改画质
  Future<LoadResult> changeQn(int qn) {
    final snapshot = plPlayerController.currentPlaybackSnapshot;
    if (!isClosed &&
        playbackOwner.isActive &&
        currentQn == qn &&
        snapshot.phase == PlaybackPhase.ready &&
        snapshot.loadId != null &&
        _matchesConfirmedLivePlan(plPlayerController.currentPlaybackPlan) &&
        plPlayerController.currentPlaybackContentKey == 'live:$roomId') {
      return Future.value(LoadResult.ready(snapshot.loadId!));
    }
    return _loadLiveQuery(requestedQn: qn);
  }

  void addDm(dynamic msg, [DanmakuContentItem<DanmakuExtra>? item]) {
    if (isClosed) return;

    if (plPlayerController.showDanmaku) {
      if (item != null && plPlayerController.enableShowLiveDanmaku.value) {
        _publishLiveDanmaku(item);
      }
      if (_followingLatest) {
        chatBuffer
          ..resume()
          ..add(msg);
        _scheduleMessageRefresh();
        scrollToBottom();
        return;
      }
    }

    chatBuffer
      ..pause()
      ..add(msg);
    _scheduleMessageRefresh();
  }

  void _publishLiveDanmaku(
    DanmakuContentItem<DanmakuExtra> item, {
    List<LiveEmoteDescriptor> emotes = const [],
    int? receivedAtUs,
  }) {
    if (isClosed) return;
    _liveDanmakuMessages.add(
      LiveDanmakuMessage(
        identity: (
          roomId,
          _chatConnection.generation,
          item.extra?.id ?? ++_liveMessageSequence,
        ),
        receivedAtUs: receivedAtUs ?? liveDanmakuNowUs(),
        text: item.text,
        color: item.color,
        type: item.type,
        selfSend: item.selfSend,
        extra: item.extra,
        emotes: emotes,
      ),
    );
  }

  @pragma('vm:notify-debugger-on-exception')
  void _danmakuListener(dynamic obj) {
    final receivedAtUs = obj is LiveMessageBody
        ? obj.receivedAtUs
        : liveDanmakuNowUs();
    try {
      // logger.i(' 原始弹幕消息 ======> ${jsonEncode(obj)}');
      switch (obj['cmd']) {
        case 'DANMU_MSG':
          final info = obj['info'];
          final first = info[0];
          final content = first[15];
          final user = content['user'];
          // final midHash = first[7];
          final uid = user['uid'];
          final msg = info[1];
          if (isBlocked(msg, uid)) {
            return;
          }
          final Map<String, dynamic> extra = jsonDecode(content['extra']);
          final name = user['base']['name'];
          BaseEmote? uemote;
          if (first[13] case Map<String, dynamic> map) {
            uemote = BaseEmote.fromJson(map);
          }
          final checkInfo = info[9];
          final liveExtra = LiveDanmaku(
            id: extra['id_str'],
            mid: uid,
            dmType: extra['dm_type'],
            ts: checkInfo['ts'],
            ct: checkInfo['ct'],
          );
          Owner? reply;
          final replyMid = extra['reply_mid'];
          if (replyMid != null && replyMid != 0) {
            reply = Owner(
              mid: replyMid,
              name: extra['reply_uname'],
            );
          }
          final emots = (extra['emots'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, BaseEmote.fromJson(v)),
          );
          final danmaku = DanmakuMsg(
            name: name,
            text: msg,
            emots: emots,
            uemote: uemote,
            extra: liveExtra,
            reply: reply,
            medalInfo:
                !DisplayPreferences.showFanMedals || user['medal'] == null
                ? null
                : UinfoMedal.fromJson(user['medal']),
          );
          final danmakuContent = DanmakuContentItem<DanmakuExtra>(
            msg,
            color: DanmakuOptions.blockColorful
                ? Colors.white
                : ColourUtils.opaqueRgb(extra['color']),
            type: danmakuPosition(extra['mode']),
            // extra['send_from_me'] is invalid
            selfSend: isLogin && uid == mid,
            extra: liveExtra,
          );
          if (uemote != null || emots?.isNotEmpty == true) {
            addDm(danmaku);
            final emoteText = msg.isEmpty && uemote != null
                ? uemote.emoticonUnique
                : msg;
            _publishLiveDanmaku(
              DanmakuContentItem<DanmakuExtra>(
                emoteText,
                extra: liveExtra,
                color: danmakuContent.color,
                type: danmakuContent.type,
                selfSend: danmakuContent.selfSend,
              ),
              receivedAtUs: receivedAtUs,
              emotes: (uemote == null ? emots! : {emoteText: uemote}).entries
                  .where(
                    (entry) =>
                        entry.key.isNotEmpty && emoteText.contains(entry.key),
                  )
                  .map(
                    (entry) => LiveEmoteDescriptor(
                      entry.key,
                      entry.value.url,
                      entry.value.width,
                      entry.value.height,
                    ),
                  )
                  .toList(growable: false),
            );
          } else {
            addDm(danmaku);
            _publishLiveDanmaku(danmakuContent, receivedAtUs: receivedAtUs);
          }
          break;
        case 'SUPER_CHAT_MESSAGE' when showSuperChat:
          final item = SuperChatItem.fromJson(obj['data'], roomId);
          superChatMsg.insert(0, item);
          addDm(item);
          if (Platform.isAndroid && AndroidHelper.isPipMode) return;
          if (plPlayerController.showDanmaku &&
              (isFullScreen || plPlayerController.isDesktopPip)) {
            fsSC.value = item.copyWith(
              endTime: math.min(
                item.endTime,
                DateTime.now().millisecondsSinceEpoch ~/ 1000 + 10,
              ),
            );
          }
          break;
        case 'WATCHED_CHANGE':
          watchedShow.value = obj['data']['text_large'];
          break;
        case 'ONLINE_RANK_COUNT':
          onlineCount.value = NumUtils.numFormat(obj['data']['count']);
          break;
        case 'ROOM_CHANGE':
          title.value = obj['data']['title'];
          break;
      }
    } catch (e, s) {
      if (kDebugMode) {
        Utils.reportError(e, s);
      }
    }
  }

  final RxInt likeClickTime = 0.obs;
  late final _likes = LiveRoomLikes(
    room: () => isClosed ? null : roomId,
    anchor: () => roomInfoH5.value?.roomInfo?.uid,
    onCount: (count) => likeClickTime.value = count,
    onReceipt: (result) {
      if (result.isSuccess) {
        SmartDialog.showToast('点赞成功');
      } else {
        result.toast();
      }
    },
  );

  void onLikeTapDown(_) => _likes.tapDown();
  void onLikeTapUp([_]) => _likes.tapUp();

  void toastNotLogin() {
    SmartDialog.showToast('账号未登录');
  }

  void onSendDanmaku([bool fromEmote = false]) {
    if (kReleaseMode && !isLogin) {
      toastNotLogin();
      return;
    }
    Get.key.currentState!.push(
      PublishRoute(
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Theme(
            data: ThemeUtils.darkTheme,
            child: LiveSendDmPanel(
              fromEmote: fromEmote,
              liveRoomController: this,
              items: savedDanmaku,
              autofocus: !fromEmote,
              onSave: (msg) {
                if (msg.isEmpty) {
                  savedDanmaku?.clear();
                  savedDanmaku = null;
                } else {
                  savedDanmaku = msg.toList();
                }
              },
            ),
          );
        },
        transitionDuration: fromEmote
            ? const Duration(milliseconds: 400)
            : PlatformUtils.isDesktop
            ? const Duration(milliseconds: 350)
            : const Duration(milliseconds: 400),
      ),
    );
  }

  void onAtUser(DanmakuMsg item) {
    savedDanmaku = [
      RichTextItem.fromStart(
        '@${item.name} ',
        rawText: item.extra.mid.toString(),
        type: .at,
        id: item.extra.id.toString(),
      ),
    ];
    onSendDanmaku();
  }

  void reportSC(SuperChatItem item) {
    final target = roomId;
    final interaction = LiveRoomInteractions(
      target,
      roomIsCurrent: () => !isClosed && roomId == target,
    );
    if (!interaction.isLogin) {
      toastNotLogin();
      return;
    }
    autoWrapReportDialog(
      Get.context!,
      ban: false,
      isCurrent: () => interaction.isCurrent,
      ReportOptions.liveDanmakuReport,
      withContent: ReportOptions.liveDanmakuReportCheck,
      contentRequired: ReportOptions.liveDanmakuReportCheck,
      (reasonType, reasonDesc, banUid) => interaction.reportSuperChat(
        item,
        ReportOptions.liveDanmakuReport['']![reasonType]!,
      ),
    );
  }
}
