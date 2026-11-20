import 'package:pili_aurora_next/features/media_catalog/domain/ranked_video.dart';

class PopularPreciousData {
  int? mediaId;
  List<HotVideoItemModel>? list;

  PopularPreciousData({this.mediaId, this.list});

  factory PopularPreciousData.fromJson(Map<String, dynamic> json) =>
      PopularPreciousData(
        mediaId: json['media_id'] as int?,
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => HotVideoItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
