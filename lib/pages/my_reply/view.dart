import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/dialog/dialog.dart';
import 'package:pili_aurora_next/common/widgets/dialog/export_import.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/features/community/application/comments/saved_replies.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:pili_aurora_next/utils/app_scheme.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/reply_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class MyReply extends ConsumerStatefulWidget {
  const MyReply({super.key});

  @override
  ConsumerState<MyReply> createState() => _MyReplyState();
}

class _MyReplyState extends ConsumerState<MyReply> with DynMixin {
  @override
  Widget build(BuildContext context) {
    final replies = ref.watch(savedRepliesProvider);
    final archive = ref.read(savedRepliesProvider.notifier);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('我的评论'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Clear',
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context: context,
                  title: const Text('Clear Local Storage?'),
                );
                if (!confirmed || !context.mounted) return;
                await archive.clear();
              },
              icon: const Icon(Icons.clear_all),
            ),
          IconButton(
            tooltip: '导出',
            onPressed: _showExportDialog,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: '导入',
            onPressed: _showImportDialog,
            icon: const Icon(Icons.file_download_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          replies.isNotEmpty
              ? ViewSliverSafeArea(
                  sliver: SliverWaterfallFlow(
                    gridDelegate: dynGridDelegate,
                    delegate: SliverChildBuilderDelegate(
                      childCount: replies.length,
                      (context, index) => ReplyItemGrpc(
                        replyLevel: 0,
                        needDivider: false,
                        replyItem: replies[index],
                        replyReply: _replyReply,
                        onDelete: (reply, childIndex) {
                          if (mounted) archive.remove(reply, childIndex);
                        },
                        onCheckReply: _onCheckReply,
                      ),
                    ),
                  ),
                )
              : const HttpError(),
        ],
      ),
    );
  }

  void _replyReply(CommentReply replyInfo, int? rpid) {
    switch (replyInfo.type.toInt()) {
      case 1:
        PiliScheme.videoPush(
          replyInfo.oid.toInt(),
          null,
        );
      case 12:
        PageUtils.toDupNamed(
          '/articlePage',
          parameters: {
            'id': replyInfo.oid.toString(),
            'type': 'read',
          },
        );
      case _:
        PageUtils.pushDynFromId(
          rid: replyInfo.oid.toString(),
          type: replyInfo.type,
        );
    }
  }

  void _onCheckReply(CommentReply replyInfo) {
    final oid = replyInfo.oid.toInt();
    ReplyUtils.onCheckReply(
      replyInfo: replyInfo,
      biliSendCommAntifraud: Pref.biliSendCommAntifraud,
      sourceId: switch (replyInfo.type.toInt()) {
        1 => IdUtils.av2bv(oid),
        _ => oid.toString(),
      },
      isManual: true,
      sourceRoute: ModalRoute.of(context),
      ownerIsCurrent: () => mounted,
    );
  }

  String _onExport() => ref.read(savedRepliesProvider.notifier).exportReplies();

  void _showExportDialog() {
    const style = TextStyle(fontSize: 14);
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: .hardEdge,
        contentPadding: const .symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text('导出至剪贴板', style: style),
            onTap: () {
              Get.back();
              exportToClipBoard(onExport: _onExport);
            },
          ),
          ListTile(
            dense: true,
            title: const Text('导出文件至本地', style: style),
            onTap: () {
              Get.back();
              exportToLocalFile(
                onExport: _onExport,
                localFileName: () => 'reply',
              );
            },
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    const style = TextStyle(fontSize: 14);
    final importReplies = ref.read(savedRepliesProvider.notifier).importReplies;
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: .hardEdge,
        contentPadding: const .symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text('从剪贴板导入', style: style),
            onTap: () {
              Get.back();
              importFromClipBoard<List<dynamic>>(
                context,
                title: '评论',
                onExport: _onExport,
                onImport: importReplies,
                showConfirmDialog: false,
              );
            },
          ),
          ListTile(
            dense: true,
            title: const Text('从本地文件导入', style: style),
            onTap: () {
              Get.back();
              importFromLocalFile<List<dynamic>>(onImport: importReplies);
            },
          ),
        ],
      ),
    );
  }
}
