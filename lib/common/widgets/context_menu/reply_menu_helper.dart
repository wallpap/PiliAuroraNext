part of 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';

Future<void> showDeleteReplyDialog(
  BuildContext context, {
  required Account account,
  required CommentReply item,
  required bool Function() isCurrent,
  required VoidCallback onDelete,
}) {
  bool submitting = false;
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('删除评论'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '确定删除这条评论吗？\n\n'),
              if (account.mid != item.member.mid.toInt())
                TextSpan(
                  text: '@${item.member.name}:\n',
                  style: TextStyle(color: ColorScheme.of(context).primary),
                ),
              TextSpan(text: item.content.message),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: submitting
                ? null
                : () async {
                    if (submitting || !isCurrent()) return;
                    final route = ModalRoute.of(context);
                    setState(() => submitting = true);
                    try {
                      final result = await CommentActions.delete(account, item);
                      if (!context.mounted ||
                          !isCurrent() ||
                          route?.isCurrent != true) {
                        return;
                      }
                      if (result.isSuccess) {
                        Navigator.of(context).pop();
                        SmartDialog.showToast('删除成功');
                        try {
                          onDelete();
                        } catch (error, stackTrace) {
                          logger.w(
                            '评论已删除，页面更新失败',
                            error: error.runtimeType,
                            stackTrace: stackTrace,
                          );
                        }
                      } else {
                        result.toast();
                      }
                    } finally {
                      if (context.mounted) setState(() => submitting = false);
                    }
                  },
            child: Text(submitting ? '删除中' : '确定'),
          ),
        ],
      ),
    ),
  );
}

void showReplyCopyDialog(
  BuildContext context,
  String message,
  Map<String, CommentEmote> emotes,
) {
  bool showEmote = false;
  showDialog(
    context: context,
    builder: (context) => Dialog(
      constraints: const BoxConstraints.tightFor(width: 380),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SelectionArea(
          contextMenuBuilder: (_, state) {
            final buttonItems = state.contextMenuButtonItems;
            if (emotes.isNotEmpty) {
              buttonItems.insertOrAdd(
                3,
                ContextMenuButtonItem(
                  label: showEmote ? '文本' : '表情',
                  onPressed: () {
                    state.hideAndClear();
                    showEmote = !showEmote;
                    (context as Element).markNeedsBuild();
                  },
                ),
              );
            }
            state.addLaunchMenuIfNeeded(buttonItems, index: 4);
            if (state.isUncollapsed) {
              buttonItems.add(
                ContextMenuButtonItem(
                  onPressed: () async {
                    final previous = CommentFilterSettings.keywords;
                    final selected = RegExp.escape(state.selectedText!);
                    final text = previous.isNotEmpty ? '|$selected' : selected;

                    final confirmed = await showConfirmDialog(
                      context: context,
                      title: const Text('是否确认评论过滤的变更：'),
                      content: Text.rich(
                        TextSpan(
                          text: previous,
                          children: [
                            TextSpan(
                              text: text,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: .bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!confirmed || !context.mounted) return;
                    try {
                      final saved = await CommentFilterSettings.appendKeyword(
                        previous,
                        text,
                      );
                      if (saved && context.mounted) {
                        SmartDialog.showToast('已保存');
                      }
                    } catch (error, stack) {
                      logger.w(
                        '评论过滤设置保存失败',
                        error: error.runtimeType,
                        stackTrace: stack,
                      );
                      if (context.mounted) SmartDialog.showToast('保存失败，请重试');
                    }
                  },
                  label: '加入过滤',
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              buttonItems: buttonItems,
              anchors: state.contextMenuAnchors,
            );
          },
          child: SingleChildScrollView(
            child: Text.rich(
              showEmote
                  ? TextSpan(
                      children: emotes.entries.mapIndexed(
                        (i, e) {
                          final emote = e.value;
                          final size = emote.size.toInt() * 25.0;
                          return TextSpan(
                            children: [
                              if (i != 0) const TextSpan(text: '\n\n'),
                              WidgetSpan(
                                child: NetworkImgLayer(
                                  src: emote.url,
                                  type: .emote,
                                  width: size,
                                  height: size,
                                ),
                              ),
                              TextSpan(text: '\n${e.key}\n${emote.url}'),
                            ],
                          );
                        },
                      ).toList(),
                    )
                  : TextSpan(text: message),
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
          ),
        ),
      ),
    ),
  );
}
