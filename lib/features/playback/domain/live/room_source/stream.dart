import 'package:pili_aurora_next/features/playback/domain/live/room_source/format.dart';

class Stream {
  String? protocolName;
  List<Format> format;

  Stream({this.protocolName, required this.format});

  factory Stream.fromJson(Map<String, dynamic> json) => Stream(
    protocolName: json['protocol_name'],
    format: (json['format'] as List<dynamic>)
        .map((e) => Format.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
