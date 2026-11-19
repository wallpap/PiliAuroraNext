import 'dart:async';

import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_info/data.dart';
import 'package:pili_aurora_next/services/live_stream/live.dart';
import 'package:pili_aurora_next/services/logger.dart';

class LiveChatConnection {
  LiveChatConnection({
    required this.currentRoom,
    required this.loadToken,
    required this.createStream,
    required this.onMessage,
    required this.onFailure,
  });

  final int? Function() currentRoom;
  final Future<LoadingState<LiveDmInfoData>> Function(int room) loadToken;
  final LiveMessageStream Function({
    required LiveDmInfoData info,
    required int roomId,
  })
  createStream;
  final void Function(dynamic) onMessage;
  final void Function(String) onFailure;

  LiveMessageStream? _stream;
  LiveDmInfoData? _token;
  Future<void>? _connecting;
  bool _wanted = false;
  int _generation = 0;
  int? _prefetchedGeneration;

  int get generation => _generation;
  bool get wantsConnection => _wanted;
  LiveDmInfoData? get token => _token;

  bool isCurrent(int generation, int room) =>
      _wanted && _generation == generation && currentRoom() == room;

  void close({bool discardToken = false}) {
    _wanted = false;
    _generation++;
    final stream = _stream;
    _stream = null;
    _connecting = null;
    if (discardToken) _token = null;
    stream?.close();
  }

  Future<void> open({
    required int room,
    void Function(int generation, int room)? prefetch,
  }) {
    if (currentRoom() != room) return Future.value();
    _wanted = true;
    final generation = _generation;
    if (prefetch != null && _prefetchedGeneration != generation) {
      _prefetchedGeneration = generation;
      prefetch(generation, room);
    }
    if (_connecting case final pending?) return pending;
    if (_stream?.isActive == true) return Future.value();
    if (_stream != null) {
      _stream = null;
      _token = null;
    }
    late final Future<void> connection;
    connection = _connect(generation, room).whenComplete(() {
      if (identical(_connecting, connection)) _connecting = null;
    });
    return _connecting = connection;
  }

  Future<void> _connect(int generation, int room) async {
    var info = _token;
    if (info == null) {
      final LoadingState<LiveDmInfoData> result;
      try {
        result = await loadToken(room);
      } catch (_) {
        return;
      }
      if (!isCurrent(generation, room)) return;
      if (result case Success(:final response)) {
        info = _token = response;
      } else {
        return;
      }
    }
    if (!isCurrent(generation, room)) return;
    final LiveMessageStream stream;
    try {
      stream = createStream(info: info, roomId: room);
    } catch (error, stack) {
      logger.w('创建直播消息连接失败', error: error.runtimeType, stackTrace: stack);
      return;
    }
    _stream = stream;
    bool valid() => isCurrent(generation, room) && identical(_stream, stream);
    late final LiveMessageConnectionResult result;
    try {
      stream.addEventListener((message) {
        if (valid()) onMessage(message);
      });
      result = await stream.init();
    } catch (error, stack) {
      logger.w('直播消息初始化失败', error: error.runtimeType, stackTrace: stack);
      result = LiveMessageConnectionResult.failed(
        '直播消息连接失败，请重试',
        cause: error,
        stackTrace: stack,
      );
    }
    if (!valid() || result.outcome == LiveMessageConnectionOutcome.connected) {
      return;
    }
    _stream = null;
    stream.close();
    if (result.outcome == LiveMessageConnectionOutcome.failed) {
      _token = null;
      onFailure(result.message ?? '直播消息连接失败，请重试');
    }
  }
}
