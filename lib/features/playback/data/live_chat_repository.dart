import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/services/web_user_agent.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_danmaku/danmaku_msg.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_block/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_block/shield_info.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_info/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_superchat/data.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/wbi_sign.dart';
import 'package:dio/dio.dart';

abstract final class LiveChatRepository {
  static Future<LoadingState<List<DanmakuMsg>?>> liveRoomDmPrefetch({
    required Object roomId,
  }) async {
    return await Request().requestApi(
      Api.liveRoomDmPrefetch,
      kind: ApiCallKind.query,
      decode: (body) => (body['data']?['room'] as List?)
          ?.map((e) => DanmakuMsg.fromPrefetch(e))
          .toList(),
      queryParameters: {'roomid': roomId},
      options: Options(
        headers: {
          'referer': 'https://live.bilibili.com/$roomId',
          'user-agent': BrowserUa.pc,
        },
      ),
    );
  }

  static Future<LoadingState<LiveDmInfoData>> liveRoomGetDanmakuToken({
    required Object roomId,
  }) async {
    final account = Accounts.heartbeat;
    try {
      return await Request().requestApi(
        Api.liveRoomDmToken,
        kind: ApiCallKind.query,
        decode: (body) => LiveDmInfoData.fromJson(body['data']),
        options: Options(extra: {'account': account}),
        queryParameters: await WbiSign.makSign({
          'id': roomId,
          'web_location': 444.8,
        }),
      );
    } catch (error, stackTrace) {
      return Error.fromException(error, stackTrace);
    }
  }

  static Future<LoadingState<ShieldInfo?>> getLiveInfoByUser(
    Object roomId, {
    Account? account,
  }) async {
    account ??= Accounts.main;
    try {
      return await Request().requestApi(
        Api.getLiveInfoByUser,
        kind: ApiCallKind.query,
        decode: (body) => LiveDmBlockData.fromJson(body['data']).shieldInfo,
        options: Options(extra: {'account': account}),
        queryParameters: await WbiSign.makSign({
          'room_id': roomId,
          'from': 0,
          'not_mock_enter_effect': 1,
          'web_location': 444.8,
        }),
      );
    } catch (error, stackTrace) {
      return Error.fromException(error, stackTrace);
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<SuperChatData>> superChatMsg(
    int roomId,
  ) async {
    return await Request().requestApi(
      Api.superChatMsg,
      kind: ApiCallKind.query,
      decode: (body) => SuperChatData.fromJson(body['data'], roomId),
      queryParameters: {
        'room_id': roomId,
      },
    );
  }
}
