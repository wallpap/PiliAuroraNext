import 'package:pili_aurora_next/utils/request_utils.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:pili_aurora_next/common/widgets/select_mask.dart';
import 'package:pili_aurora_next/models/common/badge_type.dart';
import 'package:pili_aurora_next/features/history/domain/list.dart';
import 'package:pili_aurora_next/utils/date_utils.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class HistoryItem extends StatelessWidget {
  final HistoryItemModel item;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelect;
  final bool Function() isCurrent;
  final void Function(int kid, String business) onDelete;

  const HistoryItem({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onSelect,
    required this.isCurrent,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = item.duration != null && item.duration != 0;
    int aid = item.history.oid!;
    String bvid = item.history.bvid ?? IdUtils.av2bv(aid);
    final business = item.history.business;
    final enableMultiSelect = selecting;

    final onLongPress = enableMultiSelect ? null : onSelect;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enableMultiSelect
            ? onSelect
            : () async {
                if (business?.contains('article') == true) {
                  PageUtils.toDupNamed(
                    '/articlePage',
                    parameters: {
                      'id': business == 'article-list'
                          ? '${item.history.cid}'
                          : '${item.history.oid}',
                      'type': 'read',
                    },
                  );
                } else if (business == 'live') {
                  if (item.liveStatus == 1) {
                    PageUtils.toLiveRoom(item.history.oid);
                  } else {
                    SmartDialog.showToast('直播未开播');
                  }
                } else if (business == 'pgc') {
                  PageUtils.viewPgc(
                    epId: item.history.epid,
                    progress: item.playbackProgress,
                  );
                } else if (business == 'cheese') {
                  if (item.uri?.isNotEmpty == true) {
                    PageUtils.viewPgcFromUri(
                      item.uri!,
                      isPgc: false,
                      aid: item.history.oid,
                      progress: item.playbackProgress,
                    );
                  }
                } else {
                  await PageUtils.openVideo(
                    context: context,
                    aid: aid,
                    bvid: bvid,
                    cid: item.history.cid,
                    part: item.history.page,
                    cover: item.cover,
                    title: item.title,
                    progress: item.playbackProgress,
                    isCurrent: isCurrent,
                  );
                }
              },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        double maxWidth = boxConstraints.maxWidth;
                        double maxHeight = boxConstraints.maxHeight;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              src: item.cover?.isNotEmpty == true
                                  ? item.cover
                                  : item.covers?.firstOrNull ?? '',
                              width: maxWidth,
                              height: maxHeight,
                            ),
                            if (hasDuration)
                              PBadge(
                                text: item.progress == -1
                                    ? '已看完'
                                    : '${DurationUtils.formatDuration(item.progress)}/${DurationUtils.formatDuration(item.duration)}',
                                right: 6.0,
                                bottom: 8.0,
                                type: PBadgeType.gray,
                              ),
                            if (item.isFav == 1)
                              const PBadge(
                                text: '已收藏',
                                top: 6.0,
                                right: 6.0,
                                type: PBadgeType.gray,
                              )
                            else if (item.badge?.isNotEmpty == true)
                              PBadge(
                                text: item.badge,
                                top: 6.0,
                                right: 6.0,
                                type: business == 'live' && item.liveStatus != 1
                                    ? PBadgeType.gray
                                    : PBadgeType.primary,
                              ),
                            if (hasDuration &&
                                item.progress != null &&
                                item.progress != 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: VideoProgressIndicator(
                                  color: theme.colorScheme.primary,
                                  backgroundColor:
                                      theme.colorScheme.secondaryContainer,
                                  progress: item.progress == -1
                                      ? 1
                                      : item.progress! / item.duration!,
                                ),
                              ),
                            Positioned.fill(
                              child: selectMask(
                                theme.colorScheme,
                                selected,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  content(theme),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 0,
              width: 29,
              height: 29,
              child: PopupMenuButton(
                padding: EdgeInsets.zero,
                tooltip: '功能菜单',
                icon: Icon(
                  Icons.more_vert_outlined,
                  color: theme.colorScheme.outline,
                  size: 18,
                ),
                position: PopupMenuPosition.under,
                itemBuilder: (_) => [
                  if (item.authorMid != null &&
                      item.authorName?.isNotEmpty == true)
                    AppPopupMenuItem(
                      onTap: () => Get.toNamed('/member?mid=${item.authorMid}'),
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(
                            MdiIcons.accountCircleOutline,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '访问：${item.authorName}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  if (business != 'pgc' &&
                      item.badge != '番剧' &&
                      item.tagName?.contains('动画') != true &&
                      business != 'live' &&
                      business?.contains('article') != true)
                    AppPopupMenuItem(
                      onTap: () =>
                          RequestUtils.addToWatchLater(bvid: item.history.bvid),
                      height: 38,
                      child: const Row(
                        children: [
                          Icon(Icons.watch_later_outlined, size: 16),
                          SizedBox(width: 6),
                          Text('稍后再看', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  AppPopupMenuItem(
                    onTap: () => onDelete(item.kid!, business!),
                    height: 38,
                    child: const Row(
                      children: [
                        Icon(Icons.close_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('删除记录', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget content(ThemeData theme) {
    return Expanded(
      child: Column(
        spacing: 2,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title!,
            style: TextStyle(
              fontSize: theme.textTheme.bodyMedium!.fontSize,
              height: 1.42,
              letterSpacing: 0.3,
            ),
            maxLines: item.videos! > 1 ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.history.business == 'pgc' &&
              item.showTitle?.isNotEmpty == true)
            Text(
              item.showTitle!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.outline,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const Spacer(),
          if (item.authorName?.isNotEmpty == true)
            Text(
              item.authorName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: theme.textTheme.labelMedium!.fontSize,
                color: theme.colorScheme.outline,
              ),
            ),
          Text(
            DateFormatUtils.chatFormat(item.viewAt!, isHistory: true),
            style: TextStyle(
              fontSize: theme.textTheme.labelMedium!.fontSize,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
