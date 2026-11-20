import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/path_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pili_aurora_next/features/download/domain/download_entry.dart';

extension DownloadEntryMenu on BiliDownloadEntryInfo {
  Widget moreBtn(ColorScheme colorScheme) => SizedBox(
    width: 29,
    height: 29,
    child: PopupMenuButton(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      icon: Icon(
        Icons.more_vert_outlined,
        color: colorScheme.outline,
        size: 18,
      ),
      itemBuilder: (_) => [
        AppPopupMenuItem(
          height: 38,
          child: const Text('查看详情页', style: TextStyle(fontSize: 13)),
          onTap: () {
            if (ep case final ep?) {
              if (ep.from == VideoType.pugv.name) {
                PageUtils.viewPugv(
                  seasonId: seasonId,
                  epId: ep.episodeId,
                );
              } else {
                PageUtils.viewPgc(
                  seasonId: seasonId,
                  epId: ep.episodeId,
                );
              }
              return;
            }
            PageUtils.toVideoPage(
              aid: avid,
              bvid: bvid,
              cid: cid,
              epId: ep?.episodeId,
              title: title,
              cover: cover,
              isVertical: pageData?.isVertical ?? false,
            );
          },
        ),
        if (PlatformUtils.isDesktop)
          AppPopupMenuItem(
            height: 38,
            child: const Text('打开本地文件夹', style: TextStyle(fontSize: 13)),
            onTap: () => PathUtils.openDir(entryDirPath),
          )
        else
          AppPopupMenuItem(
            height: 38,
            child: const Text('复制缓存路径', style: TextStyle(fontSize: 13)),
            onTap: () => Utils.copyText(entryDirPath),
          ),
        if (ownerId case final mid?)
          AppPopupMenuItem(
            height: 38,
            child: Text(
              '访问${ownerName != null ? '：$ownerName' : '用户主页'}',
              style: const TextStyle(fontSize: 13),
            ),
            onTap: () => Get.toNamed('/member?mid=$mid'),
          ),
      ],
    ),
  );
}
