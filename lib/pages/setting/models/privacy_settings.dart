import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/account/application/account_logout.dart';
import 'package:pili_aurora_next/features/account/presentation/account_switch_dialog.dart';
import 'package:pili_aurora_next/pages/setting/models/model.dart';
import 'package:pili_aurora_next/pages/setting/widgets/multi_select_dialog.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

List<SettingsModel> get privacySettings => [
  const SwitchModel(
    title: '增强黑名单屏蔽',
    subtitle: '信息流中过滤已拉黑作者的视频、专栏、动态和直播，并继续加载内容补位；刷新后生效',
    leading: Icon(Icons.hide_source_outlined),
    setKey: SettingBoxKey.filterBlockedAuthors,
    defaultVal: true,
    children: [
      SwitchModel(
        title: '检查合作视频作者',
        subtitle: '对列表标明的合作视频补查作者，任一作者被拉黑即屏蔽；会增加请求和加载时间，结果会缓存；刷新后生效',
        leading: Icon(Icons.group_outlined),
        setKey: SettingBoxKey.checkCooperativeAuthors,
        defaultVal: true,
      ),
    ],
  ),
  NormalModel(
    onTap: (context, setState) {
      if (!AccountLogout.hasMainAccount) {
        SmartDialog.showToast('登录后查看');
        return;
      }
      Get.toNamed('/blackListPage');
    },
    title: '黑名单管理',
    subtitle: '已拉黑用户',
    leading: const Icon(Icons.block),
  ),
  NormalModel(
    title: '切换账号',
    leading: const Icon(Icons.switch_account_outlined),
    onTap: (context, _) => showAccountSwitchDialog(context),
  ),
  const NormalModel(
    title: '退出登录',
    leading: Icon(Icons.logout_outlined),
    onTap: _logoutDialog,
  ),
];

Future<void> _logoutDialog(
  BuildContext pageContext,
  VoidCallback refresh,
) async {
  final candidates = AccountLogout.candidates;
  if (candidates.isEmpty) {
    SmartDialog.showToast('当前没有已登录账号');
    return;
  }
  final theme = Theme.of(pageContext);
  final result = await showDialog<Set<LoginAccount>>(
    context: pageContext,
    builder: (context) => MultiSelectDialog<LoginAccount>(
      title: '选择要登出的账号uid',
      initValues: const Iterable.empty(),
      values: {
        for (final account in candidates) account: account.mid.toString(),
      },
    ),
  );
  if (!pageContext.mounted || result == null || result.isEmpty) return;

  var submitting = false;
  final logout = AccountLogout(result);

  await showDialog<void>(
    context: pageContext,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> submit({required bool revoke}) async {
          final route = ModalRoute.of(dialogContext);
          if (submitting || route?.isCurrent != true) return;
          setState(() => submitting = true);
          try {
            final didCleanup = await logout.submit(revoke: revoke);
            if (didCleanup && pageContext.mounted) {
              try {
                refresh();
              } catch (error, stackTrace) {
                logger.w(
                  '退出登录后的页面刷新失败',
                  error: error.runtimeType,
                  stackTrace: stackTrace,
                );
              }
            }
            if (!dialogContext.mounted || route?.isCurrent != true) return;
            if (logout.result.isEmpty) {
              Navigator.of(dialogContext).pop();
              SmartDialog.showToast(logout.cleanupWarning ?? '所选账号已退出登录');
            }
          } catch (error, stackTrace) {
            logger.w(
              '退出登录处理失败',
              error: error.runtimeType,
              stackTrace: stackTrace,
            );
            if (dialogContext.mounted && route?.isCurrent == true) {
              SmartDialog.showToast('本地处理失败，请核对账号状态后重试');
            }
          } finally {
            if (context.mounted) setState(() => submitting = false);
          }
        }

        return AlertDialog(
          title: const Text('提示'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('确认要退出以下账号登录吗'),
                for (final account in logout.result)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      ['${account.mid}', ?logout.messages[account]].join('\n'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                '点错了',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: submitting ? null : () => submit(revoke: false),
              child: Text(
                '仅登出',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: submitting ? null : () => submit(revoke: true),
              child: Text(submitting ? '处理中' : '确认'),
            ),
          ],
        );
      },
    ),
  );
}
