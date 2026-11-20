import 'package:pili_aurora_next/features/playback/domain/pgc_detail/episode.dart';

class Section {
  String? title;
  List<EpisodeItem>? episodes;

  Section({
    this.title,
    this.episodes,
  });

  factory Section.fromJson(Map<String, dynamic> json) => Section(
    title: json['title'] as String? ?? json['name'] as String?,
    episodes: (json['episodes'] as List<dynamic>?)
        ?.map((e) => EpisodeItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
