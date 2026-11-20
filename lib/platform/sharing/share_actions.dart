import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/feedback/clipboard_actions.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:share_plus/share_plus.dart';

abstract final class ShareUtils {
  static Future<void> shareText(String text) async {
    if (PlatformUtils.isDesktop) {
      await copyText(text);
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(text: text),
      );
    } catch (error, stackTrace) {
      logger.w('分享失败', error: error.runtimeType, stackTrace: stackTrace);
      SmartDialog.showToast('分享失败，请重试');
    }
  }
}
