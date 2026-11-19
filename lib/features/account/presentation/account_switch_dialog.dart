import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/radio_widget.dart';
import 'package:pili_aurora_next/features/account/application/account_roles.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';

Future<void>? showAccountSwitchDialog(BuildContext context) {
  const roles = AccountRoles();
  final original = roles.selection();
  if (original.options.length == 1) {
    SmartDialog.showToast('请先登录');
    return Get.toNamed('/loginPage');
  }
  final colorScheme = ColorScheme.of(context);
  final selectAccount = List.of(original.roles);
  final options = original.options;
  bool quickSelect = selectAccount.every((e) => e == selectAccount.first);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        crossAxisAlignment: .start,
        mainAxisAlignment: .spaceBetween,
        children: [
          Text.rich(
            style: const TextStyle(height: 1.5),
            TextSpan(
              children: [
                const TextSpan(text: '账号切换'),
                TextSpan(
                  text: '\nmid为0时使用匿名',
                  style: TextStyle(fontSize: 14, color: colorScheme.outline),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: .compact,
              tapTargetSize: .shrinkWrap,
            ),
            onPressed: () {
              quickSelect = !quickSelect;
              (context as Element).markNeedsBuild();
            },
            child: Text(quickSelect ? '详细' : '快速'),
          ),
        ],
      ),
      titlePadding: const .only(left: 22, top: 16, right: 22, bottom: 3),
      contentPadding: const .symmetric(vertical: 5),
      actionsPadding: const .only(left: 16, right: 16, bottom: 10),
      content: SingleChildScrollView(
        child: AnimatedSize(
          curve: Curves.easeIn,
          alignment: .topCenter,
          duration: const Duration(milliseconds: 200),
          child: quickSelect
              ? Builder(
                  builder: (context) => RadioGroup<int>(
                    groupValue: selectAccount[0],
                    onChanged: (v) {
                      if (v == null) return;
                      selectAccount.fillRange(0, selectAccount.length, v);
                      (context as Element).markNeedsBuild();
                    },
                    child: Column(
                      crossAxisAlignment: .start,
                      children: options.entries
                          .map(
                            (entry) => RadioWidget<int>(
                              value: entry.key,
                              title: entry.value,
                              mainAxisSize: .max,
                              padding: PlatformUtils.isDesktop
                                  ? const .only(left: 12)
                                  : const .only(left: 12, top: 2, bottom: 2),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: .start,
                  children: AccountType.values
                      .map(
                        (e) => Builder(
                          builder: (context) => RadioGroup<int>(
                            groupValue: selectAccount[e.index],
                            onChanged: (v) {
                              selectAccount[e.index] = v!;
                              (context as Element).markNeedsBuild();
                            },
                            child: WrapRadioOptionsGroup<int>(
                              groupTitle: e.title,
                              options: options,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text('取消', style: TextStyle(color: colorScheme.outline)),
        ),
        TextButton(
          onPressed: () async {
            Get.back();
            try {
              final selected = quickSelect
                  ? List.filled(selectAccount.length, selectAccount.first)
                  : selectAccount;
              if (!await roles.apply(original, selected)) {
                SmartDialog.showToast('账号已更新，请重新打开');
              }
            } catch (error, stackTrace) {
              logger.w(
                '保存账号角色失败',
                error: error.runtimeType,
                stackTrace: stackTrace,
              );
              SmartDialog.showToast('保存账号设置失败，请重新确认');
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
