typedef UpowerRankEntry = ({
  int? mid,
  String? nickname,
  String? avatar,
  int? day,
});

typedef UpowerRankLevel = ({
  int? privilegeType,
  String? name,
  int? memberTotal,
});

class UpowerRanking {
  UpowerRanking(
    Iterable<UpowerRankEntry> ranks,
    Iterable<UpowerRankLevel> levels,
  ) : ranks = List.unmodifiable(ranks),
      levels = List.unmodifiable(levels);

  final List<UpowerRankEntry> ranks;
  final List<UpowerRankLevel> levels;
}
