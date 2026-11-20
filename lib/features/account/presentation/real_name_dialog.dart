import 'dart:async' show unawaited;

import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/account/application/real_name_query.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/core/text/string_ext.dart';
import 'package:pili_aurora_next/router/navigation_request.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

abstract final class RealNameDialog {
  static Future<void> show(String mid) async {
    final request = NavigationRequest();
    final scope = AccountScope.capture();
    bool current() => request.isCurrent && scope.isCurrent;
    try {
      final res = await queryRealName(mid, scope);
      if (!current() || Get.context?.mounted != true) return;
      if (res case Success(:final response)) {
        final show = !response.name.isNullOrEmpty;
        final dialog = showDialog<void>(
          context: Get.context!,
          builder: (context) => AlertDialog(
            title: SelectionText(
              show ? response.name! : response.rejectPage?.title ?? '',
            ),
            content: show ? null : Text(response.rejectPage?.text ?? ''),
            actions: [
              TextButton(
                onPressed: () {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('关闭'),
              ),
            ],
          ),
        );
        unawaited(
          dialog.then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              logger.w(
                '实名信息弹窗失败',
                error: error.runtimeType,
                stackTrace: stackTrace,
              );
            },
          ),
        );
      } else {
        res.toast();
      }
    } catch (error, stackTrace) {
      logger.w('实名信息查询失败', error: error.runtimeType, stackTrace: stackTrace);
      if (current()) SmartDialog.showToast('实名信息查询失败，请重试');
    } finally {
      await request.close();
    }
  }
}
