import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/image/image_save.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/stat/stat.dart';
import 'package:pili_aurora_next/features/search/domain/scoped_search.dart';
import 'package:pili_aurora_next/models/common/badge_type.dart';
import 'package:pili_aurora_next/models/common/stat_type.dart';
import 'package:pili_aurora_next/utils/date_utils.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/em.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';

class SearchArchiveCard extends ConsumerWidget {
  const SearchArchiveCard({
    super.key,
    required this.item,
  });

  final ScopedSearchArchive item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bvid = IdUtils.av2bv(item.aid);
    final regTitle = Em.regTitle(item.title);
    final titleStr = regTitle.map((e) => e.text).join();
    void onLongPress() => imageSaveDialog(
      bvid: bvid,
      title: titleStr,
      cover: item.cover,
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            onTap: () {
              if (item.isCourse) {
                PageUtils.viewPgcFromUri(item.uri, isPgc: false);
                return;
              }
              if (item.redirectUrl case final redirect?) {
                PageUtils.viewPgcFromUri(redirect);
                return;
              }
              PageUtils.toVideoPage(
                bvid: bvid,
                cid: item.cid,
                cover: item.cover,
                title: titleStr,
                isVertical: item.isVertical,
              );
            },
            child: Padding(
              padding: const .symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        final double maxWidth = boxConstraints.maxWidth;
                        final double maxHeight = boxConstraints.maxHeight;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              src: item.cover,
                              width: maxWidth,
                              height: maxHeight,
                            ),
                            if (item.isCourse)
                              const PBadge(
                                text: '课堂',
                                top: 6.0,
                                right: 6.0,
                              ),
                            if (item.duration > 0)
                              PBadge(
                                text: DurationUtils.formatDuration(
                                  item.duration,
                                ),
                                right: 6.0,
                                bottom: 6.0,
                                type: PBadgeType.gray,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  content(context, regTitle),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 12,
            width: 29,
            height: 29,
            child: PopupMenuButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert_outlined,
                color: Theme.of(context).colorScheme.outline,
                size: 17,
              ),
              position: PopupMenuPosition.under,
              itemBuilder: (context) => [
                AppPopupMenuItem(
                  height: 45,
                  onTap: () => Utils.copyText(bvid),
                  child: Row(
                    spacing: 6,
                    children: [
                      const Icon(CustomIcons.identifier_circle, size: 16),
                      Text(bvid, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                AppPopupMenuItem(
                  height: 45,
                  onTap: () async {
                    final library = ref.read(laterLibraryProvider);
                    final account = ref.read(mainAccountProvider);
                    final result = await library.add(
                      bvid: bvid,
                      account: account,
                    );
                    if (!context.mounted || !library.owns(account)) return;
                    if (result.isSuccess) {
                      SmartDialog.showToast('已添加到稍后再看');
                    } else {
                      result.toast();
                    }
                  },
                  child: const Row(
                    spacing: 6,
                    children: [
                      Icon(MdiIcons.clockTimeEightOutline, size: 16),
                      Text('稍后再看', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget content(
    BuildContext context,
    List<({bool isEm, String text})> regTitle,
  ) {
    final theme = Theme.of(context);
    String pubdate = DateFormatUtils.dateFormat(item.publishedAt);
    if (pubdate != '') pubdate += '  ';
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              TextSpan(
                children: regTitle
                    .map(
                      (e) => TextSpan(
                        text: e.text,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                          height: 1.42,
                          letterSpacing: 0.3,
                          color: e.isEm
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          Text(
            "$pubdate${item.author}",
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              color: theme.colorScheme.outline,
              overflow: TextOverflow.clip,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: item.views,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: item.danmaku,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
