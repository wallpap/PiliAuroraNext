import 'dart:async';

import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformClampingPhysics;
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/playback/application/video_danmaku_interactions.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/publish_panel_type.dart';
import 'package:pili_aurora_next/pages/common/publish/common_text_pub_page.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/pages/setting/slide_color_picker.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SendDanmakuPanel extends CommonTextPubPage {
  // video
  final int cid;
  final String bvid;
  final int progress;

  final ValueChanged<DanmakuContentItem<DanmakuExtra>> onSuccess;

  // config
  final ({int? mode, int? fontSize, Color? color})? dmConfig;
  final ValueChanged<({int mode, int fontSize, Color color})>? onSaveDmConfig;

  const SendDanmakuPanel({
    super.key,
    super.initialValue,
    super.onSave,
    required this.cid,
    required this.bvid,
    required this.progress,
    required this.onSuccess,
    this.dmConfig,
    this.onSaveDmConfig,
  });

  @override
  State<SendDanmakuPanel> createState() => _SendDanmakuPanelState();
}

class _SendDanmakuPanelState extends CommonTextPubPageState<SendDanmakuPanel> {
  late final RxInt _mode;
  late final RxInt _fontSize;
  late final Rx<Color> _color;
  final _sending = false.obs;

  final List<Color> _colorList = [
    Colors.white,
    const Color(0xFFFE0302),
    const Color(0xFFFF7204),
    const Color(0xFFFFAA02),
    const Color(0xFFFFD302),
    const Color(0xFFFFFF00),
    const Color(0xFFA0EE00),
    const Color(0xFF00CD00),
    const Color(0xFF019899),
    const Color(0xFF4266BE),
    const Color(0xFF89D5FF),
    const Color(0xFFCC0273),
    const Color(0xFF222222),
    const Color(0xFF9B9B9B),
  ];

  @override
  void initState() {
    super.initState();
    _mode = (widget.dmConfig?.mode ?? 1).obs;
    _fontSize = (widget.dmConfig?.fontSize ?? 25).obs;
    _color = (widget.dmConfig?.color ?? Colors.white).obs;
    if (AccountProfile.legacy.currentInfo?.vipStatus == 1) {
      _colorList.add(Colors.transparent);
    }
  }

  @override
  void dispose() {
    widget.onSaveDmConfig?.call((
      mode: _mode.value,
      fontSize: _fontSize.value,
      color: _color.value,
    ));
    super.dispose();
  }

  Widget get _buildColorPanel => Expanded(
    child: Obx(
      () {
        final bool isCustomColor = !_colorList.contains(_color.value);
        final int length = _colorList.length + (isCustomColor ? 1 : 0) + 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 42,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: length,
          itemBuilder: (context, index) {
            if (index == length - 1) {
              return GestureDetector(
                onTap: _showColorPicker,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(8),
                    ),
                  ),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.all(2),
                  child: Icon(
                    size: 22,
                    Icons.edit,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              );
            } else if (index == length - 2 && isCustomColor) {
              return _buildColorItem(_color.value);
            }
            return _buildColorItem(_colorList[index]);
          },
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ViewSafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            color: theme.colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInputView(),
              buildPanelContainer(Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget? get customPanel => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
    ),
    child: ListView(
      physics: platformClampingPhysics,
      padding: .only(
        top: 12,
        bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Text(
              '弹幕字号',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            _buildFontSizeItem(18, '小'),
            const SizedBox(width: 5),
            _buildFontSizeItem(25, '标准'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '弹幕样式',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            _buildPositionItem(1, '滚动'),
            const SizedBox(width: 5),
            _buildPositionItem(5, '顶部'),
            const SizedBox(width: 5),
            _buildPositionItem(4, '底部'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '弹幕颜色',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            _buildColorPanel,
          ],
        ),
      ],
    ),
  );

  Widget _buildColorItem(Color color) {
    return GestureDetector(
      onTap: () => _color.value = color,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: _color.value != color
              ? null
              : Border.all(
                  width: 2,
                  color: theme.colorScheme.primary,
                ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: color == Colors.transparent
              ? Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFFDD94DA),
                            Color(0xFF72B2EA),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPositionItem(int mode, String title) {
    return Obx(
      () => Expanded(
        child: GestureDetector(
          onTap: () => _mode.value = mode,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _mode.value == mode
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.onInverseSurface,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              title,
              style: TextStyle(
                color: _mode.value == mode
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontSizeItem(int fontSize, String title) {
    return Obx(
      () => Expanded(
        child: GestureDetector(
          onTap: () => _fontSize.value = fontSize,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _fontSize.value == fontSize
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.onInverseSurface,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              title,
              style: TextStyle(
                color: _fontSize.value == fontSize
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputView() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, right: 8),
      child: Row(
        children: [
          Obx(
            () {
              final isEmoji = panelType.value == PanelType.emoji;
              return iconButton(
                tooltip: '弹幕样式',
                iconSize: 24,
                onPressed: () => updatePanelType(isEmoji ? .keyboard : .emoji),
                icon: const Icon(Icons.text_format),
                iconColor: isEmoji
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(
              () => TextField(
                controller: editController,
                autofocus: false,
                readOnly: readOnly.value,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(100),
                ],
                onChanged: onChanged,
                textInputAction: TextInputAction.send,
                onSubmitted: onSubmitted,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: "输入弹幕内容",
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: theme.colorScheme.outline,
                  ),
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          Obx(
            () => enablePublish.value
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
          Obx(
            () => iconButton(
              tooltip: _sending.value ? '发送中' : '发送',
              iconSize: 22,
              iconColor: enablePublish.value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              onPressed: enablePublish.value && !_sending.value
                  ? onPublishThrottle
                  : null,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        title: const Text('Color Picker'),
        content: SlideColorPicker(
          color: _color.value,
          onChanged: (Color? color) {
            if (color != null) {
              _color.value = color;
            }
          },
        ),
      ),
    );
  }

  @override
  Future<void> onCustomPublish({List? pictures}) async {
    if (_sending.value) return;
    final cid = widget.cid;
    final bvid = widget.bvid;
    final text = editController.text;
    final mode = _mode.value;
    final fontSize = _fontSize.value;
    final color = _color.value;
    final isColorful = color == Colors.transparent;
    final player = PlPlayerController.instance;
    final midHash = player?.midHash;
    final ownsPlayback = player?.activePlaybackOwner?.guard();
    final interaction = VideoDanmakuInteractions(
      cid,
      mediaIsCurrent: () =>
          mounted &&
          cid == widget.cid &&
          bvid == widget.bvid &&
          (player == null ||
              (identical(player, PlPlayerController.instance) &&
                  player.cid == cid &&
                  (ownsPlayback?.call() ?? true))),
    );
    final route = ModalRoute.of(context);
    _sending.value = true;
    try {
      final res = await interaction.send(
        bvid: bvid,
        progress: widget.progress,
        message: text,
        mode: mode,
        fontSize: fontSize,
        color: isColorful ? null : color.toARGB32() & 0xFFFFFF,
        colorful: isColorful,
      );
      if (res == null || !interaction.isCurrent) return;
      if (res case Success(:final response)) {
        hasPub =
            text == editController.text &&
            mode == _mode.value &&
            fontSize == _fontSize.value &&
            color == _color.value;
        widget.onSuccess(
          DanmakuContentItem(
            text,
            color: isColorful ? Colors.white : color,
            type: switch (mode) {
              5 => DanmakuItemType.top,
              4 => DanmakuItemType.bottom,
              _ => DanmakuItemType.scroll,
            },
            selfSend: true,
            isColorful: isColorful,
            extra: response != null && midHash != null
                ? VideoDanmaku(id: response, mid: midHash)
                : null,
          ),
        );
        if (mounted && hasPub && route?.isCurrent == true) {
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
}
