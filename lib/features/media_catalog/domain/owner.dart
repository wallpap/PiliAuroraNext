import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/utils/parse_int.dart';
import 'package:hive_ce/hive.dart';

part 'owner.g.dart';

@HiveType(typeId: 3)
class Owner implements BaseOwner {
  Owner({
    this.mid,
    this.name,
    this.face,
  });
  @HiveField(0)
  @override
  int? mid;
  @HiveField(1)
  @override
  String? name;
  @HiveField(2)
  String? face;

  Owner.fromJson(Map<String, dynamic> json) {
    mid = safeToInt(json["mid"]);
    name = json["name"];
    face = json['face'];
  }

  Map<String, dynamic> toJson() => {
    'mid': mid,
    'name': name,
    'face': face,
  };
}
