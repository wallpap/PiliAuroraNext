import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pili_aurora_next/common/feedback/user_notice.dart';
import 'package:pili_aurora_next/services/logger.dart';

Future<void> copyText(
  String text, {
  bool needToast = true,
  String? toastText,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (error, stackTrace) {
    logger.w('复制失败', error: error.runtimeType, stackTrace: stackTrace);
    UserNotice.toast('复制失败，请重试');
    return;
  }
  if (needToast) UserNotice.toast(toastText ?? '已复制');
}
