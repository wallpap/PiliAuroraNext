typedef SubscriptionMedia = ({int id, int type, bool? valid});

class SubscriptionContentPage {
  const SubscriptionContentPage({
    required this.items,
    required this.hasMore,
    this.total,
  });

  final List<SubscriptionMedia> items;
  final bool hasMore;
  final int? total;
}

class SubscriptionCleanupResult {
  int removed = 0;
  int hidden = 0;
  int failed = 0;
  int pending = 0;
}
