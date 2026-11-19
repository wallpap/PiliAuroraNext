import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/text_field.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/playback/application/live_room_interactions.dart';
import 'package:pili_aurora_next/models/common/publish_panel_type.dart';
import 'package:pili_aurora_next/pages/common/publish/common_rich_text_pub_page.dart';
import 'package:pili_aurora_next/pages/live_emote/view.dart';
import 'package:pili_aurora_next/pages/live_room/controller.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart' hide TextField;

class LiveSendDmPanel extends CommonRichTextPubPage {
  final bool fromEmote;
  final LiveRoomController liveRoomController;

  const LiveSendDmPanel({
    super.key,
    super.items,
    super.onSave,
    super.autofocus = true,
    this.fromEmote = false,
    required this.liveRoomController,
  });

  @override
  State<LiveSendDmPanel> createState() => _ReplyPageState();
}

class _ReplyPageState extends CommonRichTextPubPageState<LiveSendDmPanel> {
  LiveRoomController get liveRoomController => widget.liveRoomController;
  final _sending = ValueNotifier(false);
  late final _sendButton = Listenable.merge([enablePublish, _sending]);
  late final int _roomId;

  @override
  void dispose() {
    _sending.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _roomId = liveRoomController.roomId;
    if (widget.fromEmote) {
      updatePanelType(PanelType.emoji);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewSafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            color: theme.colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildInputView(),
              Flexible(child: buildPanelContainer(Colors.transparent)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget? get customPanel => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
    ),
    child: LiveEmotePanel(
      onChoose: onChooseEmote,
      roomId: _roomId,
      onSendEmoticonUnique: (emote) {
        onCustomPublish(
          message: emote.emoticonUnique!,
          dmType: 1,
          emoticonOptions: '[object Object]',
        );
      },
    ),
  );

  Widget buildInputView() {
    return Padding(
      padding: const .only(left: 8, top: 2, right: 8),
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: panelType,
            builder: (context, panel, _) {
              final isEmoji = panel == .emoji;
              return iconButton(
                tooltip: '表情',
                onPressed: () => updatePanelType(isEmoji ? .keyboard : .emoji),
                iconSize: 22,
                icon: const Icon(Icons.emoji_emotions_outlined),
                iconColor: isEmoji
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: readOnly,
              builder: (context, readOnly, _) => RichTextField(
                key: key,
                textInputAction: .send,
                controller: editController,
                autofocus: false,
                readOnly: readOnly,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  hintText: "输入弹幕内容",
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 14),
                ),
                style: theme.textTheme.bodyLarge,
                // inputFormatters: [LengthLimitingTextInputFormatter(20)],
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: enablePublish,
            builder: (context, enabled, _) => enabled
                ? iconButton(
                    iconSize: 22,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    onPressed: () {
                      editController.clear();
                      enablePublish.value = false;
                    },
                    icon: const Icon(Icons.clear),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: _sendButton,
            builder: (context, _) => iconButton(
              tooltip: '发送',
              iconSize: 22,
              iconColor: enablePublish.value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              onPressed: enablePublish.value && !_sending.value
                  ? onPublishThrottle
                  : null,
              icon: _sending.value
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> onCustomPublish({
    String? message,
    List? pictures,
    int? dmType,
    emoticonOptions,
  }) async {
    if (!mounted || _sending.value) return;
    final owner = liveRoomController;
    if (owner.isClosed || owner.roomId != _roomId) return;
    final route = ModalRoute.of(context);
    final interaction = LiveRoomInteractions(
      _roomId,
      roomIsCurrent: () =>
          mounted &&
          identical(owner, liveRoomController) &&
          !owner.isClosed &&
          owner.roomId == _roomId &&
          route?.isCurrent == true,
    );
    final fromEditor = message == null;
    final draft = [
      for (final e in editController.items) (e.type, e.text, e.rawText, e.id),
    ];
    int replyMid = 0;
    String replyDmid = '';
    if (message == null) {
      final buffer = StringBuffer();
      for (final e in editController.items) {
        if (e.type == .at) {
          replyMid = int.parse(e.rawText);
          replyDmid = e.id!;
        } else {
          buffer.write(e.rawText);
        }
      }
      message = buffer.toString();
    }
    if (message.trim().isEmpty) return;
    _sending.value = true;
    try {
      final res = await interaction.send(
        message,
        dmType: dmType,
        emoticonOptions: emoticonOptions,
        replyMid: replyMid,
        replyId: replyDmid,
      );
      if (!mounted || res == null || !interaction.isCurrent) return;
      if (res.isSuccess) {
        hasPub =
            (fromEditor || draft.isEmpty) &&
            listEquals(draft, [
              for (final e in editController.items)
                (e.type, e.text, e.rawText, e.id),
            ]);
        if (hasPub) {
          owner
            ..savedDanmaku?.clear()
            ..savedDanmaku = null;
          Navigator.of(context).pop();
        }
        SmartDialog.showToast('发送成功');
      } else {
        res.toast();
      }
    } finally {
      if (mounted) _sending.value = false;
    }
  }

  @override
  Future<void>? onMention([bool fromClick = false]) => null;
}
