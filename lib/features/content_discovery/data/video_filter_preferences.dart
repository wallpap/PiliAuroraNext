import 'package:pili_aurora_next/core/text/keyword_pattern.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/video_filter.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class VideoFilterPreferences {
  static final _titles = KeywordPattern();
  static final _zones = KeywordPattern();

  static VideoFilter read() => VideoFilter(
    minimumDuration: Pref.minDurationForRcmd,
    minimumViews: Pref.minPlayForRcmd,
    minimumLikeRatio: Pref.minLikeRatioForRecommend,
    exemptFollowed: Pref.exemptFilterForFollowed,
    includeRelated: Pref.applyFilterToRelatedVideos,
    title: _titles.resolve(Pref.banWordForRecommend),
    zone: _zones.resolve(Pref.banWordForZone),
  );
}
