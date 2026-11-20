import 'package:pili_aurora_next/features/media_catalog/domain/owner.dart';
import 'package:pili_aurora_next/features/playback/domain/live/chat/live_emote.dart';
import 'package:pili_aurora_next/features/playback/domain/live/medals/uinfo_medal.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';

class DanmakuMsg {
  final String name;
  final String text;
  final Map<String, BaseEmote>? emots;
  final BaseEmote? uemote;
  final Owner? reply;
  final LiveDanmaku extra;
  final UinfoMedal? medalInfo;

  const DanmakuMsg({
    required this.name,
    required this.text,
    this.emots,
    this.uemote,
    this.reply,
    required this.extra,
    this.medalInfo,
  });

  factory DanmakuMsg.fromPrefetch(
    Map<String, dynamic> obj, {
    required bool showFanMedals,
  }) {
    final user = obj['user'];
    BaseEmote? uemote;
    if ((obj['emoticon']?['emoticon_unique'] as String?)?.isNotEmpty == true) {
      uemote = BaseEmote.fromJson(obj['emoticon']);
    }
    final checkInfo = obj['check_info'];
    Owner? reply;
    if (obj['reply'] case final Map map) {
      final replyMid = map['reply_mid'];
      if (replyMid != null && replyMid != 0) {
        reply = Owner(
          mid: replyMid,
          name: map['reply_uname'],
        );
      }
    }
    final medal = user['medal'];
    return DanmakuMsg(
      name: user['base']['name'],
      text: obj['text'],
      emots: (obj['emots'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, BaseEmote.fromJson(v)),
      ),
      uemote: uemote,
      reply: reply,
      extra: LiveDanmaku(
        id: obj['id_str'],
        mid: user['uid'],
        dmType: obj['dm_type'],
        ts: checkInfo['ts'],
        ct: checkInfo['ct'],
      ),
      medalInfo: !showFanMedals || medal == null
          ? null
          : UinfoMedal.fromJson(medal),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'text': text,
    'emots': ?emots,
    'uemote': ?uemote?.toJson(),
    'reply': ?reply?.toJson(),
    'extra': extra.toJson(),
    'medal': ?medalInfo?.toJson(),
  };
}
