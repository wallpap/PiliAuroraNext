import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/widgets/pair.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/action_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/post_segment_model.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/post_panel/popup_menu_text.dart';
import 'package:pili_aurora_next/pages/video/post_panel/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/mpv_convert_webp.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/webp_capture_operation.dart';
import 'package:pili_aurora_next/utils/image_utils.dart';
import 'package:pili_aurora_next/utils/path_utils.dart';

class PlayerWebpCapture {
  Future<void> cancel() async => await _webpCapture?.cancel();

  WebpCaptureOperation? _webpCapture;

  Future<void> capture({
    required BuildContext context,
    required PlPlayerController controller,
    required VideoDetailController? details,
    required bool Function() isCurrent,
  }) async {
    if (_webpCapture != null || !isCurrent()) return;
    final ctr = controller;
    final owner = ctr.activePlaybackOwner;
    if (details == null ||
        details.isClosed ||
        owner == null ||
        !owner.isActive) {
      SmartDialog.showToast('视频尚未准备好，请稍后重试');
      return;
    }
    final videoInfo = details.data;
    final snapshot = ctr.currentPlaybackSnapshot;
    final cid = ctr.cid;
    final operation = WebpCaptureOperation(
      owner: owner,
      ownsSource: () =>
          isCurrent() &&
          !details.isClosed &&
          identical(details.data, videoInfo) &&
          identical(ctr.activePlaybackOwner, owner) &&
          ctr.cid == cid &&
          ctr.currentPlaybackSnapshot.requestId == snapshot.requestId &&
          ctr.currentPlaybackSnapshot.loadId == snapshot.loadId,
    );
    _webpCapture = operation;
    try {
      await operation.run(() async {
        final ids = videoInfo.dash?.video?.availableVideoQualities;
        final currentPos = ctr.positionInMilliseconds / 1000.0;
        final duration = ctr.durationInMilliseconds / 1000.0;
        if (ids == null || ids.isEmpty || duration <= 0) {
          SmartDialog.showToast('当前视频暂不支持动态截图');
          return;
        }
        final video = details.findVideoByQa(ids.min);
        String? url = video.baseUrl;
        if (url == null || url.isEmpty) {
          SmartDialog.showToast('当前视频暂不支持动态截图');
          return;
        }
        VideoQuality qa = video.quality;
        WebpPreset preset = WebpPreset.def;
        final theme = Theme.of(context);
        final segment = Pair(first: currentPos, second: currentPos);
        final model = PostSegmentModel(
          segment: segment,
          category: SegmentType.sponsor,
          actionType: ActionType.skip,
        );
        final navigator = Navigator.of(context, rootNavigator: true);
        final dialog = WebpCaptureDialogRoute(
          operation: operation,
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('动态截图'),
            content: Column(
              spacing: 12,
              mainAxisSize: MainAxisSize.min,
              children: [
                PostPanel.segmentWidget(
                  theme,
                  item: model,
                  currentPos: () => currentPos,
                  videoDuration: duration,
                ),
                PopupMenuText(
                  title: '选择画质',
                  value: () => qa.code,
                  onSelected: (value) {
                    if (!operation.isCurrent) return false;
                    final video = details.findVideoByQa(value);
                    url = video.baseUrl;
                    qa = video.quality;
                    return false;
                  },
                  itemBuilder: (context) =>
                      (videoInfo.supportFormats ?? <FormatItem>[])
                          .map(
                            (i) => AppPopupMenuItem(
                              enabled: ids.contains(i.quality),
                              value: i.quality,
                              child: Text(i.newDesc ?? ''),
                            ),
                          )
                          .toList(),
                  getSelectTitle: (_) => qa.shortDesc,
                ),
                PopupMenuText(
                  title: 'webp预设',
                  value: () => preset,
                  onSelected: (value) {
                    if (!operation.isCurrent) return false;
                    preset = value;
                    return false;
                  },
                  itemBuilder: (context) => WebpPreset.values
                      .map(
                        (i) => AppPopupMenuItem(value: i, child: Text(i.name)),
                      )
                      .toList(),
                  getSelectTitle: (i) => '${i.name}(${i.desc})',
                ),
                Text(
                  '*转码使用CPU，速度可能慢于播放，请不要选择过长的时间段或过高画质',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (operation.isCurrent &&
                      ModalRoute.of(context)?.isCurrent == true &&
                      segment.first.isFinite &&
                      segment.second.isFinite &&
                      segment.first >= 0 &&
                      segment.first < segment.second &&
                      segment.second <= duration) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        operation.onCancel = () {
          if (dialog.isActive) navigator.removeRoute(dialog);
        };
        final success = await navigator.push(dialog) ?? false;
        operation.onCancel = null;
        if (!success || !operation.isCurrent || url == null || url!.isEmpty) {
          return;
        }

        final name =
            '$cid-${segment.first.toStringAsFixed(3)}_${segment.second.toStringAsFixed(3)}.webp';
        final file = await operation.createFile(tmpDirPath, name);
        if (file == null || !operation.isCurrent) return;
        final converted = await operation.convert(
          MpvConvertWebp(
            url!,
            file,
            segment.first,
            segment.second,
            progress: operation.progress,
            preset: preset,
          ),
        );
        if (!converted || !operation.isCurrent) return;
        final output = File(file);
        if (!output.existsSync() || await output.length() == 0) {
          if (operation.isCurrent) SmartDialog.showToast('转码未生成有效图片，请重试');
          return;
        }
        if (!operation.isCurrent) return;
        final result = await ImageUtils.saveFileImg(
          filePath: file,
          fileName: name,
        );
        if (operation.isCurrent && result != null) {
          SmartDialog.showToast(result.isSuccess ? '已保存' : '保存失败，请检查权限后重试');
        }
      });
    } finally {
      if (identical(_webpCapture, operation)) _webpCapture = null;
    }
  }
}
