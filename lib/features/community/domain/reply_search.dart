enum ReplySearchType { video, article }

class ReplySearchEntry {
  const ReplySearchEntry({
    required this.title,
    required this.cover,
    required this.url,
    this.author,
    this.category,
    this.duration,
  });

  final String title, cover, url;
  final String? author, category;
  final int? duration;
}
