import 'package:pili_aurora_next/features/playback/domain/live/room_source/stream.dart';

class Playurl {
  List<Stream> stream;

  Playurl({
    required this.stream,
  });

  factory Playurl.fromJson(Map<String, dynamic> json) => Playurl(
    stream: (json['stream'] as List<dynamic>)
        .map((e) => Stream.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
