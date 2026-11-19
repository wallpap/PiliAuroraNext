class DynamicActivityAuthor {
  const DynamicActivityAuthor({
    required this.mid,
    required this.name,
    required this.face,
    required this.level,
    required this.isSeniorMember,
    required this.hasAnnualVip,
    this.sign,
    this.pendantImage,
    this.vipStatus,
    this.officialType,
  });

  final String mid;
  final String name;
  final String face;
  final int level;
  final bool isSeniorMember;
  final bool hasAnnualVip;
  final String? sign;
  final String? pendantImage;
  final int? vipStatus;
  final int? officialType;
}

class DynamicRepostEntry {
  const DynamicRepostEntry({
    required this.id,
    required this.key,
    required this.author,
    required this.timeLabel,
    required this.content,
  });

  final String id;
  final Object key;
  final DynamicActivityAuthor? author;
  final String timeLabel;
  final List<RepostContent>? content;
}

sealed class RepostContent {
  const RepostContent();
}

final class RepostText extends RepostContent {
  const RepostText(this.text);
  final String text;
}

final class RepostEmote extends RepostContent {
  const RepostEmote(this.text, this.url, this.scale);
  final String text;
  final String url;
  final int scale;
}

enum RepostLinkKind { plain, external, series }

final class RepostLink extends RepostContent {
  const RepostLink(this.text, this.url, {this.kind = RepostLinkKind.plain});
  final String text;
  final String url;
  final RepostLinkKind kind;
}

final class RepostVote extends RepostContent {
  const RepostVote(this.title, this.id);
  final String title;
  final int id;
}

typedef RepostImage = ({String url, int width, int height});

final class RepostImages extends RepostContent {
  const RepostImages(this.images);
  final List<RepostImage> images;
}
