import 'package:pili_aurora_next/features/playback/domain/video_detail/episode.dart';

class Choice extends BaseEpisodeItem {
  String? option;

  Choice({
    super.id,
    super.cid,
    this.option,
  });

  factory Choice.fromJson(Map<String, dynamic> json) => Choice(
    id: json['id'] as int?,
    cid: json['cid'] as int?,
    option: json['option'] as String?,
  );
}
