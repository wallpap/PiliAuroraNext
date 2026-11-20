import 'package:pili_aurora_next/features/playback/data/live_chat_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/live/chat/danmaku_msg.dart';
import 'package:pili_aurora_next/features/playback/domain/live/chat_block/shield_info.dart';
import 'package:pili_aurora_next/features/playback/domain/live/chat_connection/data.dart';
import 'package:pili_aurora_next/features/playback/domain/live/superchat/item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class LiveChatQueries {
  static Future<LoadingState<List<DanmakuMsg>?>> history(int room) =>
      LiveChatRepository.liveRoomDmPrefetch(roomId: room);

  static Future<LoadingState<LiveDmInfoData>> token(int room) =>
      LiveChatRepository.liveRoomGetDanmakuToken(roomId: room);

  static Future<List<SuperChatItem>> superChat(int room) async =>
      (await LiveChatRepository.superChatMsg(room)).dataOrNull?.list ??
      const [];

  static Future<LoadingState<ShieldInfo?>> blockRules(
    Object room,
    Account account,
  ) => LiveChatRepository.getLiveInfoByUser(room, account: account);
}
