import 'package:pili_aurora_next/features/community/domain/emote/emote.dart';

class RecentEmote {
  const RecentEmote(this.emote, this.width);
  final Emote emote;
  final double? width;
  factory RecentEmote.fromJson(Map<dynamic, dynamic> json) => RecentEmote(
    Emote(text: json['text'] as String?, url: json['url'] as String?),
    (json['width'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'text': emote.text,
    'url': emote.url,
    'width': width,
  };
}
