enum ScopedSearchKind { room, user, archive, dynamic }

typedef ScopedSearchArchive = ({
  int aid,
  int cid,
  String title,
  String cover,
  String author,
  int publishedAt,
  int duration,
  int views,
  int danmaku,
  bool isVertical,
  bool isCourse,
  String uri,
  String? redirectUrl,
});
