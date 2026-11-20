import 'package:pili_aurora_next/features/member_space/domain/profiles/space_season_series/meta.dart';

class SpaceSsModel {
  SpaceSsMeta? meta;

  SpaceSsModel({this.meta});

  factory SpaceSsModel.fromJson(Map<String, dynamic> json) => SpaceSsModel(
    meta: json["meta"] == null ? null : SpaceSsMeta.fromJson(json["meta"]),
  );
}
