import 'package:pili_aurora_next/features/account/application/account_preferences.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

int _dialogRevision = 0;

Future<void> toggleIncognito() async {
  if (!AccountPrivacy.canEnable) {
    SmartDialog.showToast('请先登录');
    return;
  }
  final newVal = !AccountPrivacy.enabled;
  final request = ++_dialogRevision;
  final owner = AccountPrivacy.owner;
  if (newVal) AccountPrivacy.enableTemporarily();
  if (newVal) {
    SmartDialog.dismiss();
    final result = await SmartDialog.show<bool>(
      clickMaskDismiss: false,
      usePenetrate: true,
      displayTime: const Duration(seconds: 2),
      alignment: Alignment.bottomCenter,
      builder: (context) {
        final theme = Theme.of(context);
        final style = TextStyle(
          color: theme.colorScheme.onSecondaryContainer,
        );
        return ColoredBox(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: EdgeInsets.only(
              top: 15,
              left: 20,
              right: 20,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 15,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(MdiIcons.incognito, size: 20),
                    const SizedBox(width: 10),
                    Text('已进入无痕模式', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '搜索不携带身份信息\n'
                  '不产生查询或播放记录\n'
                  '点赞等其它操作不受影响\n'
                  '播放进度信息跟随视频取流\n'
                  '上次观看分p信息跟随主账号\n'
                  '(前往隐私设置了解详情)',
                  style: theme.textTheme.bodySmall,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        SmartDialog.dismiss(result: true);
                      },
                      child: Text('保存为永久', style: style),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () {
                        SmartDialog.dismiss();
                        SmartDialog.showToast('已设为临时无痕模式');
                      },
                      child: Text('仅本次（默认）', style: style),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (request != _dialogRevision ||
        !AccountPrivacy.owns(owner) ||
        result != true) {
      return;
    }
    try {
      await AccountPrivacy.saveEnabled();
      if (request == _dialogRevision && AccountPrivacy.owns(owner)) {
        SmartDialog.showToast('已设为永久无痕模式');
      }
    } catch (_) {
      if (request == _dialogRevision && AccountPrivacy.owns(owner)) {
        SmartDialog.showToast('无痕模式保存失败，请重试');
      }
    }
  } else {
    SmartDialog.dismiss(result: false);
    try {
      await AccountPrivacy.disable();
    } catch (_) {
      if (request == _dialogRevision && AccountPrivacy.owns(owner)) {
        SmartDialog.showToast('无痕模式保存失败，请重试');
      }
      return;
    }
    if (request != _dialogRevision || !AccountPrivacy.owns(owner)) return;
    SmartDialog.show(
      clickMaskDismiss: false,
      usePenetrate: true,
      displayTime: const Duration(seconds: 1),
      alignment: Alignment.bottomCenter,
      builder: (context) {
        final theme = Theme.of(context);
        return ColoredBox(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: EdgeInsets.only(
              top: 15,
              left: 20,
              right: 20,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 15,
            ),
            child: Row(
              children: [
                const Icon(MdiIcons.incognitoOff, size: 20),
                const SizedBox(width: 10),
                Text('已退出无痕模式', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}
