import 'package:dio/dio.dart' show CancelToken;
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_info_h5/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/data.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/connectivity_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

class LiveRoomQueries {
  CancelToken? _details;

  Future<LoadingState<RoomInfoH5Data>?> details(
    int room, {
    required bool Function() current,
  }) async {
    _details?.cancel();
    final request = _details = CancelToken();
    final account = Accounts.heartbeat;
    try {
      final result = await LiveHttp.liveRoomInfoH5(
        roomId: room,
        account: account,
        cancelToken: request,
      );
      return identical(_details, request) &&
              current() &&
              identical(account, Accounts.heartbeat)
          ? result
          : null;
    } finally {
      if (identical(_details, request)) _details = null;
    }
  }

  static Future<LoadingState<RoomPlayInfoData>?> playback({
    required int room,
    required Account account,
    required int? quality,
    required bool audioOnly,
    required CancelToken cancelToken,
    required bool Function() current,
  }) async {
    quality ??= await ConnectivityUtils.isWiFi
        ? Pref.liveQuality
        : Pref.liveQualityCellular;
    if (!current()) return null;
    final result = await LiveHttp.liveRoomInfo(
      roomId: room,
      account: account,
      qn: quality,
      onlyAudio: audioOnly,
      cancelToken: cancelToken,
    );
    return current() ? result : null;
  }

  static Future<void> recordEntry(int room) async {
    final account = Accounts.heartbeat;
    if (!account.isLogin || Pref.historyPause) return;
    await VideoHttp.roomEntryAction(account: account, roomId: room);
  }

  void dispose() {
    _details?.cancel();
    _details = null;
  }
}
