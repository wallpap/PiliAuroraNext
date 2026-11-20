import 'package:pili_aurora_next/features/playback/domain/live/room_source/playurl.dart';

class PlayurlInfo {
  Playurl? playurl;

  PlayurlInfo({
    this.playurl,
  });

  factory PlayurlInfo.fromJson(Map<String, dynamic> json) => PlayurlInfo(
    playurl: json['playurl'] == null
        ? null
        : Playurl.fromJson(json['playurl'] as Map<String, dynamic>),
  );
}
