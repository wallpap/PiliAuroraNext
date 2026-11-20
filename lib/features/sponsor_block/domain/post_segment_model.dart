import 'package:pili_aurora_next/core/types/pair.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/action_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';

class PostSegmentModel {
  PostSegmentModel({
    required this.segment,
    required this.category,
    required this.actionType,
  });
  Pair<double, double> segment;
  SegmentType category;
  ActionType actionType;
}
