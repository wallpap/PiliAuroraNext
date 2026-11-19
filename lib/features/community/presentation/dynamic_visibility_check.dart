import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart' show Get, GetNavigation;
import 'package:material_ui/material_ui.dart';

Future<void> checkPublishedDynamic({
  Object? id,
  String? dynText,
  bool isManual = false,
  AccountScope? owner,
}) async {
  final account = owner ?? AccountScope.capture();
  bool isCurrent() => account.isCurrent && Get.context?.mounted == true;
  if (isManual || DynamicDetails.checkAfterPublish) {
    try {
      if (id != null) {
        if (!isManual) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        if (!isCurrent()) return;
        final res = await DynamicDetails.legacy.checkPublicVisibility(id);
        if (!isCurrent()) return;
        if (res is Error) {
          SmartDialog.showToast('暂时无法确认动态可见性：$res');
          return;
        }
        final isSuccess = res.data;
        showDialog(
          context: Get.context!,
          barrierDismissible: isManual,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            final color = isSuccess ? colorScheme.primary : colorScheme.error;
            final actions = [
              if (!isSuccess)
                TextButton(
                  onPressed: () {
                    Get.back();
                    Utils.copyText('https://www.bilibili.com/opus/$id');
                    Get.toNamed(
                      '/webview',
                      parameters: {
                        'url':
                            'https://www.bilibili.com/h5/comment/appeal?${ThemeUtils.themeUrl(colorScheme.isDark)}',
                      },
                    );
                  },
                  child: const Text('申诉'),
                ),
              if (!isManual)
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '关闭',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
            ];
            return AlertDialog(
              title: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: .middle,
                      child: isSuccess
                          ? Icon(
                              size: 22,
                              color: color,
                              Icons.check_circle_outline_rounded,
                            )
                          : Icon(
                              size: 22,
                              color: color,
                              Icons.highlight_off_outlined,
                            ),
                    ),
                    TextSpan(
                      text: ' 动态检查结果',
                      style: TextStyle(color: color),
                    ),
                  ],
                ),
              ),
              content: SelectionText(
                '${isSuccess ? '未登录状态下可以查看该动态。' : '未登录状态下无法查看该动态，请检查可见范围。'}${dynText != null ? ' \n\n动态内容: $dynText' : ''}',
              ),
              actions: actions.isEmpty ? null : actions,
            );
          },
        );
      }
    } catch (e, stackTrace) {
      logger.w('check dyn error: $e', error: e, stackTrace: stackTrace);
    }
  }
}
