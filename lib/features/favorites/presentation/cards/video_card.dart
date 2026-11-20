import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/image/image_save.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/select_mask.dart';
import 'package:pili_aurora_next/common/widgets/stat/stat.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/common/widgets/badge_type.dart';
import 'package:pili_aurora_next/common/widgets/stat/stat_type.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_detail/media.dart';
import 'package:pili_aurora_next/pages/audio/view.dart';
import 'package:pili_aurora_next/core/time/date_format.dart';
import 'package:pili_aurora_next/core/time/duration_format.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

// 收藏视频卡片 - 水平布局
class FavVideoCardH extends StatelessWidget {
  final FavDetailItemModel item;
  final int? index;
  final bool isOwner;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  const FavVideoCardH({
    super.key,
    required this.item,
    this.index,
    this.isOwner = false,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.onOpen,
    this.onRemove,
  });

  bool get isSort => onOpen == null;

  @override
  Widget build(BuildContext context) {
    final enableMultiSelect = selecting;
    final colorScheme = ColorScheme.of(context);

    final onLongPress = isSort || enableMultiSelect
        ? null
        : isOwner && !enableMultiSelect
        ? onSelect
        : () => imageSaveDialog(
            title: item.title,
            cover: item.cover,
            bvid: item.bvid,
          );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isSort
            ? null
            : enableMultiSelect
            ? onSelect
            : () {
                // 1、9 表示已删除，其他状态仍允许打开视频。
                if (const [1, 9].contains(item.attr)) {
                  Get.toNamed('/member?mid=${item.upper?.mid}');
                  return;
                }

                switch (item.type) {
                  case 12:
                    AudioPage.toAudioPage(
                      oid: item.id!,
                      itemType: 3,
                      from: AudioPlaylistSource.audioCard,
                    );
                    break;
                  case 24:
                    PageUtils.viewPgc(
                      seasonId: item.ogv!.seasonId,
                      epId: item.id,
                    );
                    break;
                  default:
                    onOpen?.call();
                    break;
                }
              },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
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
                          src: item.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                        PBadge(
                          text: DurationUtils.formatDuration(item.duration),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                        if (item.type == 12)
                          const PBadge(
                            text: '音频',
                            top: 6.0,
                            right: 6.0,
                            type: PBadgeType.gray,
                          )
                        else
                          PBadge(
                            text: item.ogv?.typeName,
                            top: 6.0,
                            right: 6.0,
                            bottom: null,
                            left: null,
                          ),
                        if (!isSort)
                          Positioned.fill(
                            child: selectMask(
                              colorScheme,
                              selected,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              content(context, colorScheme, isOwner),
            ],
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context, ColorScheme colorScheme, bool isOwner) {
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title!,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.type == 24 && item.intro?.isNotEmpty == true)
                Text(
                  item.intro!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                ),
              const Spacer(),
              Text(
                '${DateFormatUtils.dateFormat(item.favTime)} ${item.upper?.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1,
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              if (item.type != 24)
                Row(
                  spacing: 8,
                  children: [
                    StatWidget(
                      type: StatType.play,
                      value: item.cntInfo?.play,
                    ),
                    StatWidget(
                      type: StatType.danmaku,
                      value: item.cntInfo?.danmaku,
                    ),
                  ],
                ),
            ],
          ),
          if (isOwner)
            Positioned(
              right: 0,
              bottom: -8,
              child: iconButton(
                icon: const Icon(Icons.clear),
                tooltip: '取消收藏',
                iconColor: colorScheme.outline,
                onPressed: onRemove,
              ),
            ),
        ],
      ),
    );
  }
}
