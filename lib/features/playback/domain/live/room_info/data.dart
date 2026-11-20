import 'package:pili_aurora_next/models/remote/live/live_feed_index/watched_show.dart';
import 'package:pili_aurora_next/features/playback/domain/live/room_info/anchor_info.dart';
import 'package:pili_aurora_next/features/playback/domain/live/room_info/room_info.dart';

class RoomInfoH5Data {
  RoomInfo? roomInfo;
  AnchorInfo? anchorInfo;
  WatchedShow? watchedShow;

  RoomInfoH5Data({
    this.roomInfo,
    this.anchorInfo,
    this.watchedShow,
  });

  factory RoomInfoH5Data.fromJson(Map<String, dynamic> json) => RoomInfoH5Data(
    roomInfo: json['room_info'] == null
        ? null
        : RoomInfo.fromJson(json['room_info'] as Map<String, dynamic>),
    anchorInfo: json['anchor_info'] == null
        ? null
        : AnchorInfo.fromJson(json['anchor_info'] as Map<String, dynamic>),
    watchedShow: json['watched_show'] == null
        ? null
        : WatchedShow.fromJson(json['watched_show'] as Map<String, dynamic>),
  );
}
