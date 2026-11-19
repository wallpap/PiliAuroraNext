import 'package:pili_aurora_next/models/model_video.dart';

class VideoFilter {
  const VideoFilter({
    required this.minimumDuration,
    required this.minimumViews,
    required this.minimumLikeRatio,
    required this.exemptFollowed,
    required this.includeRelated,
    required this.title,
    required this.zone,
  });

  final int minimumDuration;
  final int minimumViews;
  final int minimumLikeRatio;
  final bool exemptFollowed;
  final bool includeRelated;
  final RegExp? title;
  final RegExp? zone;

  bool blocksRecommendation(BaseVideoItemModel item) =>
      !(item.isFollowed && exemptFollowed) && blocksVideo(item);

  bool blocksVideo(BaseVideoItemModel item) =>
      (item.duration > 0 && item.duration < minimumDuration) ||
      blocksTitleOrEngagement(item.title, item.stat.like, item.stat.view);

  bool blocksTitleOrEngagement(String name, int? like, int? view) =>
      title?.hasMatch(name) == true ||
      (view != null &&
          ((view > -1 && view < minimumViews) ||
              (like != null &&
                  like > -1 &&
                  like * 100 < minimumLikeRatio * view)));

  bool blocksZone(String? name) => name != null && zone?.hasMatch(name) == true;
}
