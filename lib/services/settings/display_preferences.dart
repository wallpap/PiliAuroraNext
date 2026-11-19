import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class DisplayPreferences {
  static int get imageQuality => Pref.picQuality;
  static bool get showFanMedals => Pref.showMedal;
  static bool get darkVideoPage => Pref.darkVideoPage;
  static double get uiScale => Pref.uiScale;
  static bool get landscapeMemberPage => Pref.horizontalMemberPage;
  static bool get expandVideoIntro => Pref.alwaysExpandIntroPanel;
  static bool get expandLandscapeVideoIntro => Pref.expandIntroPanelH;
  static bool get showVideoDispute => Pref.showArgueMsg;
  static bool get showOnlineViewers => Pref.enableOnlineTotal;
  static bool get slideDismissReplyPage => Pref.slideDismissReplyPage;
  static bool get showBatteryLevel => Pref.showBatteryLevel;

  static Future<void> saveImageQuality(int quality) =>
      GStorage.setting.put(SettingBoxKey.defaultPicQa, quality);
}
