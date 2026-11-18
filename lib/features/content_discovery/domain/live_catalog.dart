import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_list.dart';
import 'package:pili_aurora_next/models/remote/live/live_second_list/tag.dart';

class LiveCatalog {
  LiveCatalog({
    this.followed,
    this.areas,
    List<LiveSecondTag> tags = const [],
  }) : tags = List.unmodifiable(tags);
  final LiveCardList? followed, areas;
  final List<LiveSecondTag> tags;
}
