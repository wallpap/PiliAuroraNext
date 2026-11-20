import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/dialog/report.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_interactions.dart';
import 'package:pili_aurora_next/features/playback/application/video_danmaku_interactions.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

Future<void> recallVideoDanmaku(
  VideoDanmakuInteractions interaction,
  int id, {
  required void Function() onRecalled,
}) async {
  final result = await interaction.recall(id);
  if (!interaction.isCurrent) return;
  if (result is Success) {
    onRecalled();
    SmartDialog.showToast('删除成功');
  } else if (result is Error) {
    result.toast();
  }
}

Future<void> reportVideoDanmaku(
  BuildContext context,
  VideoDanmakuInteractions interaction,
  VideoDanmaku entry, {
  required DanmakuBlockRules blockRules,
}) {
  if (!interaction.isLogin) return SmartDialog.showToast('请先登录');
  return autoWrapReportDialog(
    context,
    ReportOptions.danmakuReport,
    isCurrent: () => interaction.isCurrent,
    withContent: ReportOptions.danmakuReportCheck,
    contentRequired: ReportOptions.danmakuReportCheck,
    (reason, description, block) async =>
        await interaction.report(
          entry,
          reason: reason,
          description: description,
          blockRules: block ? blockRules : null,
        ) ??
        const Error('账号或视频已切换，请重新打开举报页面'),
  );
}

Future<void> reportLiveDanmaku(
  BuildContext context, {
  required int roomId,
  required String msg,
  required LiveDanmaku extra,
  bool Function()? roomIsCurrent,
}) {
  final interaction = LiveRoomInteractions(
    roomId,
    roomIsCurrent: () => context.mounted && (roomIsCurrent?.call() ?? true),
  );
  if (!interaction.isLogin) return SmartDialog.showToast('请先登录');
  return autoWrapReportDialog(
    context,
    ban: false,
    isCurrent: () => interaction.isCurrent,
    ReportOptions.liveDanmakuReport,
    withContent: ReportOptions.liveDanmakuReportCheck,
    contentRequired: ReportOptions.liveDanmakuReportCheck,
    (reasonType, reasonDesc, banUid) => interaction.reportMessage(
      msg,
      extra,
      reason: ReportOptions.liveDanmakuReport['']![reasonType]!,
      reasonId: reasonType,
    ),
  );
}
