import 'package:pili_aurora_next/features/playback/data/live_chat_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_danmaku/danmaku_msg.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_block/shield_info.dart';
import 'package:pili_aurora_next/models/remote/live/live_dm_info/data.dart';
import 'package:pili_aurora_next/models/remote/live/live_superchat/item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

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
