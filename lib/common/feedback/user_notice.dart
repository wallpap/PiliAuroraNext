import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class UserNotice {
  static void toast(String message) => SmartDialog.showToast(message);

  static void warning(String message) =>
      SmartDialog.showNotify(msg: message, notifyType: .warning);
}
