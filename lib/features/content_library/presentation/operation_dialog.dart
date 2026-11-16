import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

/// 弹窗持有提交锁和失败草稿，成功只关闭自己的路由。
Future<bool> libraryConfirm(
  BuildContext context, {
  required String title,
  required Future<LoadingState<void>> Function() submit,
  required bool Function() isCurrent,
  required bool Function() ownsResult,
}) async {
  var saving = false;
  String? error;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: error == null ? null : Text(error!),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!isCurrent()) {
                          setState(() => error = '内容或账号已更新，请重新打开');
                          return;
                        }
                        final route = ModalRoute.of(context);
                        setState(() => saving = true);
                        final result = await submit();
                        if (!context.mounted ||
                            route?.isCurrent != true ||
                            !ownsResult()) {
                          return;
                        }
                        if (result.isSuccess) {
                          Navigator.of(context).pop(true);
                        } else {
                          setState(() {
                            saving = false;
                            error = result.toString();
                          });
                        }
                      },
                child: Text(saving ? '提交中' : '确认'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
