import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_discovery/application/video_feedback.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/recommendation/result.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/services/logger.dart';

class VideoFeedbackDialog extends StatefulWidget {
  const VideoFeedbackDialog({
    super.key,
    required this.item,
    required this.operation,
    required this.isCurrent,
    this.onRemove,
  });

  final BaseSimpleVideoItemModel item;
  final VideoFeedback operation;
  final bool Function() isCurrent;
  final VoidCallback? onRemove;

  @override
  State<VideoFeedbackDialog> createState() => _VideoFeedbackDialogState();
}

class _VideoFeedbackDialogState extends State<VideoFeedbackDialog> {
  bool _pending = false;
  bool get _current =>
      mounted && widget.isCurrent() && widget.operation.isCurrent;

  Future<void> _submit({
    Reason? reason,
    Reason? feedback,
    bool cancel = false,
  }) async {
    if (_pending || !_current) return;
    final item = widget.item;
    final operation = widget.operation;
    final route = ModalRoute.of(context);
    setState(() => _pending = true);
    try {
      final result = await operation.submit(
        reasonId: reason?.id,
        feedbackId: feedback?.id,
        cancel: cancel,
      );
      if (!mounted ||
          !_current ||
          route?.isCurrent == false ||
          !identical(item, widget.item) ||
          !identical(operation, widget.operation)) {
        return;
      }
      if (result.isSuccess) {
        Navigator.of(context).pop();
        SmartDialog.showToast(
          cancel ? '已撤销反馈' : reason?.toast ?? feedback?.toast ?? '反馈成功',
        );
        if (!cancel) {
          try {
            widget.onRemove?.call();
          } catch (error, stackTrace) {
            // 页面刷新失败不能改写已经确认的反馈结果。
            logger.w(
              '反馈已成功，更新视频列表失败',
              error: error.runtimeType,
              stackTrace: stackTrace,
            );
          }
        }
      } else {
        result.toast();
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final points = item is RcmdVideoItemAppModel ? item.threePoint : null;
    final reasons =
        points?.dislikeReasons?.where((reason) => reason.id != null).toList() ??
        [];
    final feedbacks =
        points?.feedbacks?.where((reason) => reason.id != null).toList() ?? [];
    Widget choices(List<Reason> values, {bool feedback = false}) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          SearchText(
            text: value.name ?? '其他原因',
            onTap: (_) => _submit(
              reason: feedback ? null : value,
              feedback: feedback ? value : null,
            ),
          ),
      ],
    );
    return SimpleDialog(
      contentPadding: const .fromLTRB(24, 16, 24, 24),
      children: [
        if (_pending)
          const Padding(
            padding: .only(bottom: 12),
            child: Text('提交中…', textAlign: .center),
          ),
        if (item is RcmdVideoItemAppModel) ...[
          if (reasons.isEmpty && feedbacks.isEmpty)
            const Text('推荐反馈信息不完整，请刷新列表后重试'),
          IgnorePointer(
            ignoring: _pending,
            child: Column(
              crossAxisAlignment: .start,
              children: [
                if (reasons.isNotEmpty) ...[
                  const Text('我不想看'),
                  const SizedBox(height: 5),
                  choices(reasons),
                ],
                if (feedbacks.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  const Text('反馈'),
                  const SizedBox(height: 5),
                  choices(feedbacks, feedback: true),
                ],
              ],
            ),
          ),
        ] else ...[
          const Text('web端暂不支持精细选择', textAlign: .center),
          const SizedBox(height: 5),
          FilledButton.tonal(
            onPressed: _pending ? null : _submit,
            child: const Text('点踩'),
          ),
        ],
        const Divider(),
        FilledButton.tonal(
          onPressed: _pending ? null : () => _submit(cancel: true),
          child: const Text('撤销'),
        ),
      ],
    );
  }
}
