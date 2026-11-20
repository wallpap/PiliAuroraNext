import 'package:pili_aurora_next/features/community/domain/comments/reply_sort_type.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class CommentPreferences {
  static ReplySortType get defaultSort => Pref.replySortType;
  static ReplySortType get threadSort => Pref.reply2SortType;
  static int get minimumUserLevel => Pref.minimumReplyUserLevel;
  static int? get lineLimit => Pref.replyLengthLimit;
  static bool get openSearchLinks => Pref.enableWordRe;
  static bool get checkSendVisibility => Pref.biliSendCommAntifraud;
  static bool get checkSendCriteria => Pref.enableCommAntifraud;
}
