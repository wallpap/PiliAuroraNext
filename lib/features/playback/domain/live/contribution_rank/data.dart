import 'package:pili_aurora_next/features/playback/domain/live/contribution_rank/item.dart';

class LiveContributionRankData {
  List<LiveContributionRankItem>? item;

  LiveContributionRankData({
    this.item,
  });

  factory LiveContributionRankData.fromJson(Map<String, dynamic> json) =>
      LiveContributionRankData(
        item: (json['item'] as List<dynamic>?)
            ?.map(
              (e) =>
                  LiveContributionRankItem.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}
