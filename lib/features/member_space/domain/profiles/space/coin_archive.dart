import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';

class CoinArchive {
  int? count;
  List<SpaceArchiveItem>? item;

  CoinArchive({this.count, this.item});

  factory CoinArchive.fromJson(Map<String, dynamic> json) => CoinArchive(
    count: json['count'] as int?,
    item: (json['item'] as List<dynamic>?)
        ?.map((e) => SpaceArchiveItem.fromJson(e))
        .toList(),
  );
}
