import 'package:pili_aurora_next/features/download/presentation/entry_menu.dart';

import 'dart:async';
import 'dart:io';

import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/dialog/dialog.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:pili_aurora_next/common/widgets/select_mask.dart';
import 'package:pili_aurora_next/common/widgets/badge_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';
import 'package:pili_aurora_next/features/download/presentation/downloading_page.dart';
import 'package:pili_aurora_next/services/cache/image_cache.dart';
import 'package:pili_aurora_next/core/time/duration_format.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/download/application/download_progress.dart';
import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

class DetailItem extends ConsumerWidget {
  const DetailItem({
    super.key,
    required this.entry,
    this.progress,
    this.onToggle,
    this.onUpdate,
    this.onDelete,
    required this.showTitle,
    this.currentTask,
    //
    this.enableMultiSelect = false,
    this.checked,
    this.onSelect,
    this.playlist,
  });

  final BiliDownloadEntryInfo entry;
  final ChangeNotifier? progress;
  final Future<void> Function()? onToggle;
  final Future<void> Function()? onUpdate;
  final VoidCallback? onDelete;
  final bool showTitle;
  final DownloadTask? currentTask;
  //
  final bool enableMultiSelect;
  final bool? checked;
  final ValueChanged<BiliDownloadEntryInfo>? onSelect;
  final List<BiliDownloadEntryInfo> Function()? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = currentTask;
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    final cid = entry.source?.cid ?? entry.pageData?.cid;
    final canDel = onDelete != null;

    void onLongPress() => canDel && !enableMultiSelect
        ? showDialog(
            context: context,
            builder: (_) => SimpleDialog(
              clipBehavior: Clip.hardEdge,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                DialogOption(
                  onPressed: () async {
                    Get.back();
                    final confirmed = await showConfirmDialog(
                      context: context,
                      title: const Text('确定删除该视频？'),
                    );
                    if (!confirmed || !context.mounted) return;
                    onDelete?.call();
                  },
                  child: const Text('删除', style: TextStyle(fontSize: 14)),
                ),
                DialogOption(
                  onPressed: () async {
                    Get.back();
                    await onUpdate?.call();
                  },
                  child: const Text('更新弹幕', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          )
        : null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () async {
          if (!canDel) {
            Get.to(const DownloadingPage());
            return;
          }
          if (enableMultiSelect) {
            onSelect?.call(entry);
            return;
          }
          if (entry.isCompleted) {
            await PageUtils.toVideoPage(
              aid: entry.avid,
              cid: cid!,
              cover: entry.cover,
              title: entry.showTitle,
              isVertical: entry.pageData?.isVertical ?? false,
              extraArguments: {
                'sourceType': SourceType.file,
                'entry': entry,
                'offlineEntries': playlist?.call() ?? [entry],
                'dirPath': entry.entryDirPath,
              },
            );
            if (context.mounted) {
              Timer(const Duration(milliseconds: 400), () {
                if (context.mounted) {
                  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
                  progress?.notifyListeners();
                }
              });
            }
          } else {
            await onToggle?.call();
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
            spacing: 10,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cover = File(
                          path.join(entry.entryDirPath, PathUtils.coverName),
                        );
                        final maxWidth = constraints.maxWidth;
                        final maxHeight = constraints.maxHeight;
                        return ClipRRect(
                          borderRadius: Style.mdRadius,
                          child: Image(
                            image: LocalImageProvider(
                              cover,
                              decodeTarget: ImageDecodeTarget.forDisplay(
                                Size(maxWidth, maxHeight),
                                MediaQuery.devicePixelRatioOf(context),
                                BoxFit.cover,
                              ),
                            ),
                            width: maxWidth,
                            height: maxHeight,
                            fit: BoxFit.cover,
                            colorBlendMode: NetworkImgLayer.reduce
                                ? BlendMode.modulate
                                : null,
                            color: NetworkImgLayer.reduce
                                ? NetworkImgLayer.reduceLuxColor
                                : null,
                            errorBuilder: (_, _, _) => NetworkImgLayer(
                              src: entry.cover,
                              width: maxWidth,
                              height: maxHeight,
                              cacheWidth: entry.pageData?.cacheWidth,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (entry.videoQuality case final videoQuality?)
                    PBadge(
                      text: VideoQuality.fromCode(videoQuality).shortDesc,
                      right: 6.0,
                      top: 6.0,
                      type: PBadgeType.gray,
                    ),
                  if (progress != null)
                    ListenableBuilder(
                      listenable: progress!,
                      builder: (_, _) {
                        final durationMs = entry.totalTimeMilli;
                        final progress = ref
                            .read(downloadProgressStoreProvider)
                            .read(cid!, durationMs);
                        if (progress != null) {
                          final positionMs = progress.positionMs;
                          final elapsed = positionMs == null
                              ? '已看完'
                              : DurationUtils.formatDuration(
                                  positionMs ~/ 1000,
                                );
                          final timeLabel =
                              positionMs == null || durationMs <= 0
                              ? elapsed
                              : '$elapsed/${DurationUtils.formatDuration(durationMs ~/ 1000)}';
                          return Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Column(
                              crossAxisAlignment: .end,
                              children: [
                                Padding(
                                  padding: const .only(right: 6, bottom: 3),
                                  child: PBadge(
                                    isStack: false,
                                    text: timeLabel,
                                    type: .gray,
                                  ),
                                ),
                                if (positionMs == null || durationMs > 0)
                                  VideoProgressIndicator(
                                    color: theme.colorScheme.primary,
                                    backgroundColor:
                                        theme.colorScheme.secondaryContainer,
                                    progress: positionMs == null
                                        ? 1
                                        : positionMs / durationMs,
                                  ),
                              ],
                            ),
                          );
                        }
                        return PBadge(
                          text: DurationUtils.formatDuration(
                            entry.totalTimeMilli ~/ 1000,
                          ),
                          right: 6.0,
                          bottom: 7.0,
                          type: PBadgeType.gray,
                        );
                      },
                    )
                  else if (entry.totalTimeMilli != 0)
                    PBadge(
                      text: DurationUtils.formatDuration(
                        entry.totalTimeMilli ~/ 1000,
                      ),
                      right: 6,
                      bottom: 7,
                      type: PBadgeType.gray,
                    ),
                  Positioned.fill(
                    child: selectMask(
                      theme.colorScheme,
                      checked ?? false,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      spacing: 5,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showTitle ? entry.title : entry.showTitle,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: theme.textTheme.bodyMedium!.fontSize,
                            height: 1.42,
                            letterSpacing: 0.3,
                          ),
                          maxLines: showTitle
                              ? entry.ep != null
                                    ? 1
                                    : 2
                              : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (showTitle) ...[
                          if (entry.pageData?.part case final part?)
                            if (part != entry.title)
                              Text(
                                part,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          if (entry.ep?.showTitle case final showTitle?)
                            Text(
                              showTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ],
                    ),
                    if (entry.isCompleted) ...[
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Text(
                          '${CacheManager.formatSize(entry.totalBytes)}${entry.ownerName != null ? '  ${entry.ownerName}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: outline,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: entry.moreBtn(theme.colorScheme),
                      ),
                    ] else
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: task != null
                            ? Consumer(
                                builder: (context, ref, _) {
                                  final progress = ref.watch(
                                    downloadCurrentTaskProvider,
                                  );
                                  return entryProgress(
                                    theme,
                                    progress != null &&
                                            identical(
                                              progress.identity,
                                              task.identity,
                                            ) &&
                                            progress.generation ==
                                                task.generation
                                        ? progress
                                        : null,
                                  );
                                },
                              )
                            : entryProgress(theme),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget entryProgress(ThemeData theme, [DownloadTaskProgress? progress]) {
    final status = progress?.status ?? entry.status;
    final total = progress?.totalBytes ?? entry.totalBytes;
    final downloaded = progress?.downloadedBytes ?? entry.downloadedBytes;
    return progressWidget(
      statusMsg: status.message,
      progressStr: total == 0
          ? ''
          : '${CacheManager.formatSize(downloaded)}/${CacheManager.formatSize(total)}',
      progress: total == 0 ? 0 : downloaded / total,
      color: currentTask != null && status != DownloadStatus.pause
          ? theme.colorScheme.primary
          : theme.colorScheme.outline,
      highlightColor: theme.highlightColor,
    );
  }

  Widget progressWidget({
    required String statusMsg,
    required String progressStr,
    required double progress,
    required Color color,
    required Color highlightColor,
  }) {
    return Column(
      spacing: 6,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                statusMsg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  color: color,
                ),
              ),
            ),
            Flexible(
              child: Text(
                progressStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          // ignore: deprecated_member_use
          year2023: true,
          minHeight: 2.5,
          borderRadius: Style.mdRadius,
          color: color,
          backgroundColor: highlightColor,
          value: progress,
        ),
      ],
    );
  }
}
