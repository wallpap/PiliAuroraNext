import 'package:pili_aurora_next/features/watch_later/presentation/watch_later_action.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/features/content_discovery/application/video_feedback.dart';
import 'package:pili_aurora_next/models/model_video.dart';
import 'package:pili_aurora_next/models/remote/space/space_archive/item.dart';
import 'package:pili_aurora_next/features/account/application/account_preferences.dart';
import 'package:pili_aurora_next/features/account/presentation/incognito_action.dart';
import 'package:pili_aurora_next/features/member_space/application/member_moderation.dart';
import 'package:pili_aurora_next/common/widgets/dialog/video_feedback.dart';
import 'package:pili_aurora_next/pages/video/ai_conclusion/view.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/controller.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class _VideoCustomAction {
  final String title;
  final Widget icon;
  final VoidCallback onTap;
  const _VideoCustomAction(this.title, this.icon, this.onTap);
}

class VideoPopupMenu extends StatefulWidget {
  final double? iconSize;
  final double menuItemHeight;
  final BaseSimpleVideoItemModel videoItem;
  final VoidCallback? onRemove;

  const VideoPopupMenu({
    super.key,
    required this.iconSize,
    required this.videoItem,
    this.onRemove,
    this.menuItemHeight = 45,
  });

  @override
  State<VideoPopupMenu> createState() => _VideoPopupMenuState();
}

class _VideoPopupMenuState extends State<VideoPopupMenu> {
  Future<void> _confirmBlock(
    BaseSimpleVideoItemModel item,
    VoidCallback? onRemove,
  ) async {
    final memberId = item.owner.mid;
    if (!mounted || !identical(item, widget.videoItem) || memberId == null) {
      return;
    }
    final moderation = MemberModeration.capture();
    final route = ModalRoute.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提示'),
        content: Text(
          '确定拉黑:${item.owner.name}($memberId)?'
          '\n\n注：被拉黑的Up可以在隐私设置-黑名单管理中解除',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '点错了',
              style: TextStyle(color: ColorScheme.of(dialogContext).outline),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    bool sourceIsCurrent() =>
        mounted &&
        identical(item, widget.videoItem) &&
        route?.isCurrent != false;
    if (confirm != true || !sourceIsCurrent()) return;
    if (!moderation.isCurrent) {
      SmartDialog.showToast('账号已切换，请重试');
      return;
    }
    final result = await moderation.block(memberId);
    if (!sourceIsCurrent() || !moderation.isCurrent) return;
    if (result.isSuccess) {
      onRemove?.call();
    } else {
      result.toast();
    }
  }

  void _showFeedback(BaseSimpleVideoItemModel item, VoidCallback? onRemove) {
    if (!mounted || !identical(item, widget.videoItem)) return;
    final operation = VideoFeedback.capture(item);
    if (operation.loginError case final message?) {
      SmartDialog.showToast(message);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => VideoFeedbackDialog(
        item: item,
        operation: operation,
        isCurrent: () => mounted && identical(item, widget.videoItem),
        onRemove: onRemove,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.iconSize;
    final menuItemHeight = widget.menuItemHeight;
    final videoItem = widget.videoItem;
    final onRemove = widget.onRemove;
    return PopupMenuButton(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_outlined,
        color: Theme.of(context).colorScheme.outline,
        size: iconSize,
      ),
      position: PopupMenuPosition.under,
      itemBuilder: (context) =>
          [
                if (videoItem.bvid?.isNotEmpty == true) ...[
                  _VideoCustomAction(
                    videoItem.bvid!,
                    const Icon(CustomIcons.identifier_circle, size: 16),
                    () => Utils.copyText(videoItem.bvid!),
                  ),
                  if (AccountScope.signedIn)
                    _VideoCustomAction(
                      '稍后再看',
                      const Icon(MdiIcons.clockTimeEightOutline, size: 16),
                      () => addToWatchLater(bvid: videoItem.bvid),
                    ),
                  if (videoItem.cid != null && Pref.enableAi)
                    _VideoCustomAction(
                      'AI总结',
                      const Icon(CustomIcons.ai_circle, size: 16),
                      () async {
                        final res = await UgcIntroController.getAiConclusion(
                          videoItem.bvid!,
                          videoItem.cid!,
                          videoItem.owner.mid,
                        );
                        if (res != null && context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              child: Padding(
                                padding: const .symmetric(vertical: 14),
                                child: AiConclusionPanel.buildContent(
                                  context,
                                  Theme.of(context),
                                  res,
                                  tap: false,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
                if (videoItem is! SpaceArchiveItem) ...[
                  _VideoCustomAction(
                    '访问：${videoItem.owner.name}',
                    const Icon(MdiIcons.accountCircleOutline, size: 16),
                    () => Get.toNamed('/member?mid=${videoItem.owner.mid}'),
                  ),
                  _VideoCustomAction(
                    '不感兴趣',
                    const Icon(MdiIcons.thumbDownOutline, size: 16),
                    () => _showFeedback(videoItem, onRemove),
                  ),
                  _VideoCustomAction(
                    '拉黑：${videoItem.owner.name}',
                    const Icon(MdiIcons.cancel, size: 16),
                    () => _confirmBlock(videoItem, onRemove),
                  ),
                ],
                _VideoCustomAction(
                  "${AccountPrivacy.enabled ? '退出' : '进入'}无痕模式",
                  AccountPrivacy.enabled
                      ? const Icon(MdiIcons.incognitoOff, size: 16)
                      : const Icon(MdiIcons.incognito, size: 16),
                  toggleIncognito,
                ),
              ]
              .map(
                (e) => AppPopupMenuItem(
                  height: menuItemHeight,
                  onTap: e.onTap,
                  child: Row(
                    children: [
                      e.icon,
                      const SizedBox(width: 6),
                      Text(e.title, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
