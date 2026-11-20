enum VideoType {
  ugc(type: 3),
  pgc(type: 4),
  pugv(type: 10, replyType: 33),
  ;

  final int type;
  final int replyType;
  const VideoType({
    required this.type,
    this.replyType = 1,
  });
}
