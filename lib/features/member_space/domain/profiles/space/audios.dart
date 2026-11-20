import 'package:pili_aurora_next/features/member_space/domain/profiles/space_audio/item.dart';

class Audios {
  int? count;
  List<SpaceAudioItem>? item;

  Audios({this.count, this.item});

  factory Audios.fromJson(Map<String, dynamic> json) => Audios(
    count: json['count'] as int?,
    item: (json['item'] as List<dynamic>?)
        ?.map((e) => SpaceAudioItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
