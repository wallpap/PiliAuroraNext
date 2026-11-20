import 'package:pili_aurora_next/features/playback/domain/live/room_info/base_info.dart';

class AnchorInfo {
  BaseInfo? baseInfo;

  AnchorInfo({this.baseInfo});

  factory AnchorInfo.fromJson(Map<String, dynamic> json) => AnchorInfo(
    baseInfo: json['base_info'] == null
        ? null
        : BaseInfo.fromJson(json['base_info'] as Map<String, dynamic>),
  );
}
