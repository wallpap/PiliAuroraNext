import 'package:pili_aurora_next/features/playback/domain/live/room_source/codec.dart';

class Format {
  String? formatName;
  List<CodecItem> codec;

  Format({
    this.formatName,
    required this.codec,
  });

  factory Format.fromJson(Map<String, dynamic> json) => Format(
    formatName: json['format_name'],
    codec: (json['codec'] as List<dynamic>)
        .map((e) => CodecItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
