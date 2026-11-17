import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/topic_sort_by_conf.dart';

class TopicCursor {
  const TopicCursor(this.offset, this.seen, this.sort);
  final String? offset;
  final Set<String> seen;
  final TopicSortByConf? sort;
}
