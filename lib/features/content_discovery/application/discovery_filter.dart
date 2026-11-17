import 'package:pili_aurora_next/models/model_video.dart';
import 'package:pili_aurora_next/services/blocked_authors.dart';
import 'package:pili_aurora_next/utils/global_data.dart';
import 'package:pili_aurora_next/utils/media_author_filter.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

/// 推荐与历史发现页共用作者规则；缓存仅保存作者身份，不缓存屏蔽结论。
class DiscoveryFilter {
  const DiscoveryFilter();

  Future<void>? prepare() => BlockedAuthors.ensureLoaded();

  Iterable<CooperativeVideo> authorsToCheck(Object? items) {
    if (!Pref.filterBlockedAuthors ||
        !Pref.checkCooperativeAuthors ||
        GlobalData().blackMids.isEmpty) {
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

  List<T> filter<T>(
    Iterable<T> source, {
    Iterable<T> existing = const [],
    bool deduplicate = false,
  }) {
    if (!Pref.filterBlockedAuthors && !deduplicate) return source.toList();
    final seen = existing
        .map(MediaAuthorFilter.contentKey)
        .whereType<Object>()
        .toSet();
    return source.where((item) {
      if (Pref.filterBlockedAuthors &&
          MediaAuthorFilter.isBlocked(
            item,
            BlockedAuthors.contains,
            includeCoauthors: Pref.checkCooperativeAuthors,
          )) {
        return false;
      }
      final key = MediaAuthorFilter.contentKey(item);
      return key == null || seen.add(key);
    }).toList();
  }
}
