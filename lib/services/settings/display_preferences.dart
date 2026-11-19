import 'dart:ui' show Color;

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
  static bool get showAvatarDecoration => Pref.showDecorate;
  static bool get showEmoteTooltips => Pref.enableEmoteTooltip;
  static double get toastOpacity => Pref.defaultToastOp;
  static Color? get dimOverlayColor => Pref.reduceLuxColor;
  static int get galleryQuality => Pref.previewQ;
  static bool get playLivePhotos => Pref.enableLivePhoto;
  static bool get landscapeImagePreview => Pref.horizontalPreview;
  static bool get showImageMenu => Pref.enableImgMenu;

  static Future<void> saveImageQuality(int quality) =>
      GStorage.setting.put(SettingBoxKey.defaultPicQa, quality);
}
