import 'package:pili_aurora_next/features/playback/domain/live/chat_block/shield_user_list.dart';
import 'package:pili_aurora_next/core/collections/iterable_ext.dart';

class ShieldInfo {
  List<ShieldUserList>? shieldUserList;
  List<String>? keywordList;

  ShieldInfo({
    this.shieldUserList,
    this.keywordList,
  });

  factory ShieldInfo.fromJson(Map<String, dynamic> json) => ShieldInfo(
    shieldUserList: (json['shield_user_list'] as List<dynamic>?)
        ?.map((e) => ShieldUserList.fromJson(e as Map<String, dynamic>))
        .toList(),
    keywordList: (json['keyword_list'] as List?)?.fromCast(),
  );
}
