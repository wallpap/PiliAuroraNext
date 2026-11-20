import 'package:pili_aurora_next/features/media_catalog/domain/horizontal_video.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';

class SeasonArchive extends HorizontalVideoModel {
  SeasonArchive.fromJson(Map<String, dynamic> json) {
    aid = json['aid'];
    bvid = json['bvid'];
    cover = json['pic'];
    title = json['title'];
    pubdate = json['pubdate'];
    duration = json['duration'];
    stat = ArchiveStat.fromJson(json['stat']);
    owner = ArchiveOwner.fromJson(json);
  }
}

class ArchiveOwner extends BaseOwner {
  ArchiveOwner.fromJson(Map<String, dynamic> json) {
    mid = json['upMid'];
    name = '';
  }
}

class ArchiveStat extends BaseStat {
  ArchiveStat.fromJson(Map<String, dynamic> json) {
    view = json['view'];
    danmu = json['danmaku'];
  }
}
