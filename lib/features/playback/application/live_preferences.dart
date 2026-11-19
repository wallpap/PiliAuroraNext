import 'package:pili_aurora_next/models/common/super_chat_type.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class LivePreferences {
  static int get desktopQuality => Pref.liveQuality;
  static SuperChatType get superChat => Pref.superChatType;
  static double get fullScreenSuperChatWidth => Pref.fullScreenSCWidth;
}
