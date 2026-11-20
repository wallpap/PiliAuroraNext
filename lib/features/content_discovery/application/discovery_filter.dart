import 'package:pili_aurora_next/features/content_discovery/application/blocked_authors.dart';
import 'package:pili_aurora_next/features/content_discovery/application/media_author_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/data/author_filter_preferences.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';

/// 推荐与历史发现页共用作者规则；缓存仅保存作者身份，不缓存屏蔽结论。
class DiscoveryFilter {
  const DiscoveryFilter();

  bool get enabled => AuthorFilterPreferences.filterBlockedAuthors;
  bool get includeCoauthors => AuthorFilterPreferences.checkCooperativeAuthors;
  bool contains(int? mid) => BlockedAuthors.contains(mid);

  Future<void>? prepare() => BlockedAuthors.ensureLoaded();

  Iterable<CooperativeVideo> authorsToCheck(Object? items) {
    if (!enabled || !includeCoauthors || !BlockedAuthors.hasBlockedAuthors) {
      return const [];
    }
    return MediaAuthorFilter.videos(items).where(
      (video) =>
          video.authors.isCooperation &&
          video.authors.mids == null &&
          !BlockedAuthors.contains(video.ownerMid),
    );
  }

  bool needsAuthorCheck(Object? item) => authorsToCheck(item).isNotEmpty;

  bool isBlocked(Object? item) =>
      enabled && blocks(item, checkCoauthors: includeCoauthors);

  bool blocks(Object? item, {required bool checkCoauthors}) =>
      MediaAuthorFilter.isBlocked(
        item,
        contains,
        includeCoauthors: checkCoauthors,
      );

  List<T> filter<T>(
    Iterable<T> source, {
    Iterable<T> existing = const [],
    bool deduplicate = false,
  }) {
    if (!enabled && !deduplicate) return source.toList();
    final seen = existing
        .map(MediaAuthorFilter.contentKey)
        .whereType<Object>()
        .toSet();
    return source.where((item) {
      if (isBlocked(item)) return false;
      final key = MediaAuthorFilter.contentKey(item);
      return key == null || seen.add(key);
    }).toList();
  }
}
