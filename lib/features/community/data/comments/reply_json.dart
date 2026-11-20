import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';

ReplyInfo decodeWebReply(Map json) {
  final content = Map.of(json['content'] as Map)..remove('members');
  final member = json['member'] as Map;
  final emotes = content['emote'] as Map?;
  return ReplyInfo.create()..mergeFromProto3Json(
    {
      ...json,
      'id': json['rpid'],
      'member': {
        ...member,
        'name': member['uname'],
        'face': member['avatar'],
        'level': member['level_info']['current_level'],
        'vipStatus': member['vip']['vipStatus'],
        'vipType': member['vip']['vipType'],
        'officialVerifyType': member['official_verify']['type'],
      },
      'content': {
        ...content,
        'emotes': emotes?.map(
          (key, value) => MapEntry(key, {...value, 'size': value['meta']['size']}),
        ),
      },
    },
    ignoreUnknownFields: true,
  );
}
