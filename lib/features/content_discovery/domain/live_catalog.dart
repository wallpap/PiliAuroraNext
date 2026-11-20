import 'package:pili_aurora_next/features/content_discovery/domain/live/feed_index/card_list.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live/second_list/tag.dart';

class LiveCatalog {
  LiveCatalog({
    this.followed,
    this.areas,
    List<LiveSecondTag> tags = const [],
  }) : tags = List.unmodifiable(tags);
  final LiveCardList? followed, areas;
  final List<LiveSecondTag> tags;
}
