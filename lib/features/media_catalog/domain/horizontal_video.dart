import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/dimension.dart';

abstract class HorizontalVideoModel extends BaseVideoItemModel {
  bool? isPugv;
  int? seasonId;

  int? roomId;
  bool? isLive;

  Dimension? dimension;

  String? badge;

  num? progress;

  String? redirectUrl;

  // search
  List<({bool isEm, String text})>? titleList;
}
