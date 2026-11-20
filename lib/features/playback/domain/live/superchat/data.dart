import 'package:pili_aurora_next/features/playback/domain/live/superchat/item.dart';

class SuperChatData {
  List<SuperChatItem>? list;

  SuperChatData({this.list});

  factory SuperChatData.fromJson(
    Map<String, dynamic> json,
    int roomId, {
    required bool showFanMedals,
  }) =>
      SuperChatData(
        list: (json['list'] as List<dynamic>?)
            ?.map(
              (e) => SuperChatItem.fromJson(
                e as Map<String, dynamic>,
                roomId,
                showFanMedals: showFanMedals,
              ),
            )
            .toList(),
      );
}
