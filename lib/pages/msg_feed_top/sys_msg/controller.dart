import 'package:pili_aurora_next/services/messaging/models/msg_unread_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/services/messaging/models/msg_sys/data.dart';
import 'package:pili_aurora_next/services/messaging/feed.dart';
import 'package:pili_aurora_next/services/messaging/feed_adapters.dart';
import 'package:pili_aurora_next/services/messaging/feed_notifier.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';

final systemMessageFeedProvider =
    NotifierProvider<SystemMessageFeedNotifier, FeedSnapshot<MsgSysItem>>(
      SystemMessageFeedNotifier.new,
      isAutoDispose: true,
    );

class SystemMessageFeedNotifier extends FeedNotifier<MsgSysItem> {
  @override
  FeedHandle<MsgSysItem> createHandle(MessagingSession session) => FeedHandle(
    session: session,
    request: MessagingFeedAdapters.system,
    idOf: (item) => item.id,
    delete: MessagingFeedAdapters.deleteSystem,
    acknowledge: MessagingFeedAdapters.acknowledgeSystem,
    notifyUnreadOnRefresh: true,
    readType: MsgUnReadType.sysMsg,
  );
}
