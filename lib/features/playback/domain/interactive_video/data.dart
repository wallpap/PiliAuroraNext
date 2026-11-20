import 'package:pili_aurora_next/features/playback/domain/interactive_video/edges.dart';

class EdgeInfoData {
  Edges? edges;

  EdgeInfoData({
    this.edges,
  });

  factory EdgeInfoData.fromJson(Map<String, dynamic> json) => EdgeInfoData(
    edges: json['edges'] == null
        ? null
        : Edges.fromJson(json['edges'] as Map<String, dynamic>),
  );
}
