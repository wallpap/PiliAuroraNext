import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:pili_aurora_next/common/widgets/button/toolbar_icon_button.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/controller.dart'
    show RichTextType, RichTextEditingDeltaReplacement;
import 'package:pili_aurora_next/common/widgets/flutter/text_field/text_field.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformClampingPhysics;
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_video_tools.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart' show FilePicModel;
import 'package:pili_aurora_next/pages/common/publish/common_rich_text_pub_page.dart';
import 'package:pili_aurora_next/pages/emote/view.dart';
import 'package:pili_aurora_next/pages/video/reply_search_item/view.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/latex_to_unicode.dart';
import 'package:pili_aurora_next/utils/path_utils.dart';
import 'package:pili_aurora_next/services/settings/display_preferences.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart' hide TextField;

class ReplyPage extends CommonRichTextPubPage {
  final int oid;
  final int root;
  final int parent;
  final int replyType;
  final CommentReply? replyItem;
  final String? hint;
  final bool canUploadPic;
  final ValueChanged<CommentReply?>? onSuccess;
  final CommentVideoTools? videoTools;

  const ReplyPage({
    super.key,
    super.items,
    super.imageLengthLimit,
    super.onSave,
    required this.oid,
    required this.root,
    required this.parent,
    required this.replyType,
    this.replyItem,
    this.hint,
    this.canUploadPic = true,
    this.onSuccess,
    this.videoTools,
  });

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends CommonRichTextPubPageState<ReplyPage> {
  bool _capturingScreenshot = false;
  final _publishing = ValueNotifier(false);
  final _syncToDynamic = ValueNotifier(false);
  final _latexOn = ValueNotifier(false);
  late final _publishButton = Listenable.merge([enablePublish, _publishing]);

  @override
  void dispose() {
    _publishing.dispose();
    _syncToDynamic.dispose();
    _latexOn.dispose();
    super.dispose();
  }

  @override
  void initTheme() {
    theme = darkVideoPage ? ThemeUtils.darkTheme : Theme.of(context);
  }

  late final darkVideoPage =
      Get.currentRoute == '/videoV' && DisplayPreferences.darkVideoPage;

  @override
  Widget build(BuildContext context) {
    Widget child = ViewSafeArea(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...buildInputView(),
              buildImagePreview(),
              Flexible(child: buildPanelContainer(Colors.transparent)),
            ],
          ),
        ),
      ),
    );
    return darkVideoPage ? Theme(data: theme, child: child) : child;
  }

  @override
  Widget? get customPanel => EmotePanel(onChoose: onChooseEmote);

  Widget buildImagePreview() {
    return ValueListenableBuilder(
      valueListenable: images,
      builder: (context, images, _) {
        if (images.isNotEmpty) {
          return SizedBox(
            height: 85,
            child: ListView.separated(
              scrollDirection: .horizontal,
              padding: const .fromLTRB(15, 0, 15, 10),
              itemCount: images.length,
              itemBuilder: (_, index) => buildImage(index, 75),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }

  List<Widget> buildInputView() {
    return [
      Padding(
        padding: const EdgeInsets.only(
          top: 12,
          right: 15,
          left: 15,
          bottom: 10,
        ),
        child: ValueListenableBuilder(
          valueListenable: readOnly,
          builder: (context, readOnly, _) => RichTextField(
            key: key,
            controller: editController,
            minLines: 4,
            maxLines: 8,
            autofocus: false,
            readOnly: readOnly,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            focusNode: focusNode,
            decoration: InputDecoration(
              hintText: widget.hint ?? "输入回复内容",
              border: InputBorder.none,
              hintStyle: const TextStyle(fontSize: 14),
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ),
      Divider(
        height: 1,
        color: theme.dividerColor.withValues(alpha: 0.1),
      ),
      Container(
        height: 52,
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Row(
          children: [
            emojiBtn,
            if (widget.root == 0) ...[
              const SizedBox(width: 8),
              ToolbarIconButton(
                tooltip: '图片',
                selected: false,
                icon: widget.canUploadPic
                    ? const Icon(Icons.image, size: 22)
                    : const Icon(Icons.image_not_supported, size: 22),
                onPressed: widget.canUploadPic
                    ? onPickImage
                    : () => SmartDialog.showToast('当前评论区不支持发送图片'),
              ),
            ],
            const SizedBox(width: 8),
            atBtn,
            const SizedBox(width: 8),
            latexBtn,
            const SizedBox(width: 8),
            moreBtn,
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _syncToDynamic,
              builder: (context, sync, _) => ToolbarIconButton(
                tooltip: '转到动态',
                onPressed: () => _syncToDynamic.value = !_syncToDynamic.value,
                icon: const Icon(
                  CustomIcons.repeat_rounded_rotate_90,
                  size: 22,
                ),
                selected: sync,
              ),
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: _publishButton,
              builder: (context, _) => FilledButton.tonal(
                onPressed: enablePublish.value && !_publishing.value
                    ? onPublishThrottle
                    : null,
                style: FilledButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget buildMorePanel() {
    double height = context.isTablet ? 300 : 170;
    final keyboardHeight = controller.keyboardHeight;
    if (keyboardHeight != 0) {
      height = max(height, keyboardHeight);
    }

    Widget item({
      required VoidCallback onTap,
      required Icon icon,
      required String title,
    }) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          spacing: 5,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.onInverseSurface,
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final isRoot = widget.root == 0;
    final color = theme.colorScheme.onSurfaceVariant;
    late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
      maxCrossAxisExtent: 65,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: 25,
    );

    return SizedBox(
      height: height,
      child: GridView(
        physics: platformClampingPhysics,
        padding: const EdgeInsets.only(left: 12, bottom: 12, right: 12),
        gridDelegate: gridDelegate,
        children: [
          item(
            onTap: () async {
              final ({String title, String url})? res = await Get.to(
                ReplySearchPage(type: widget.replyType, oid: widget.oid),
              );
              if (mounted && res != null) {
                onInsertText(
                  '${res.title} ',
                  RichTextType.common,
                  rawText: '${res.url} ',
                );
              }
            },
            icon: Icon(Icons.post_add, size: 28, color: color),
            title: '插入内容',
          ),
          if (widget.videoTools case final video?) ...[
            item(
              onTap: () {
                if (video.position() case final position?) {
                  onInsertText(
                    ' ${DurationUtils.formatDuration(position.inSeconds)} ',
                    RichTextType.common,
                  );
                }
              },
              icon: Icon(Icons.my_location, size: 28, color: color),
              title: '视频进度',
            ),
            if (isRoot && widget.canUploadPic)
              item(
                onTap: () async {
                  if (imageList.length >= limit) {
                    SmartDialog.showToast('最多选择$limit张图片');
                    return;
                  }
                  if (_capturingScreenshot || _publishing.value) return;
                  _capturingScreenshot = true;
                  String? temporaryPath;
                  final identity = AccountScope.capture();
                  final route = ModalRoute.of(context);
                  var invalidated = false;
                  void onNavigation() {
                    if (!identical(routeObserver.currentRoute, route)) {
                      invalidated = true;
                    }
                  }

                  bool pageCurrent() =>
                      mounted &&
                      !invalidated &&
                      (route?.isCurrent ?? true) &&
                      identity.isCurrent &&
                      !_publishing.value;
                  bool Function() current = pageCurrent;
                  routeObserver.addNavigationListener(onNavigation);
                  try {
                    final capture = video.capture();
                    if (capture != null) {
                      current = () => pageCurrent() && capture.isCurrent();
                    }
                    final image = await capture?.read();
                    if (image == null) {
                      if (current()) SmartDialog.showToast('截图失败，请重试');
                      return;
                    }
                    try {
                      final png = await image.toByteData(format: .png);
                      if (!current()) return;
                      if (png == null) throw StateError('截图编码未返回数据');
                      temporaryPath =
                          '$tmpDirPath/${Utils.generateRandomString(8)}.png';
                      await File(temporaryPath)
                          .writeAsBytes(png.buffer.asUint8List());
                      if (current() && imageList.length < limit) {
                        addDraftImage(FilePicModel(path: temporaryPath));
                        temporaryPath = null; // 图片草稿取得临时文件所有权。
                      }
                    } finally {
                      image.dispose();
                    }
                  } catch (error, stackTrace) {
                    logger.w(
                      '评论截图失败',
                      error: error.runtimeType,
                      stackTrace: stackTrace,
                    );
                    if (current()) SmartDialog.showToast('截图失败，请重试');
                  } finally {
                    routeObserver.removeNavigationListener(onNavigation);
                    _capturingScreenshot = false;
                    if (temporaryPath != null) {
                      try {
                        final file = File(temporaryPath);
                        if (file.existsSync()) await file.delete();
                      } catch (error, stackTrace) {
                        logger.w(
                          '评论截图临时文件清理失败',
                          error: error.runtimeType,
                          stackTrace: stackTrace,
                        );
                      }
                    }
                  }
                },
                icon: Icon(
                  Icons.enhance_photo_translate_outlined,
                  size: 28,
                  color: color,
                ),
                title: '视频截图',
              ),
          ],
        ],
      ),
    );
  }

  @override
  Future<void> onPublish() => onCustomPublish();

  @override
  Future<void> onCustomPublish({List? pictures}) async {
    if (!mounted || _publishing.value) return;
    final identity = AccountScope.capture();
    final account = identity.account;
    if (!account.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final target = widget;
    final route = ModalRoute.of(context);
    final text = editController.text;
    final rawText = editController.rawText;
    final draft = getRichContent();
    final images = pictureDraft;
    final syncToDynamic = _syncToDynamic.value;
    final message = target.replyItem != null && target.replyItem!.root != 0
        ? ' 回复 @${target.replyItem!.member.name} : $rawText'
        : rawText;
    final atNameToMid = <String, int>{};
    bool isCurrent() =>
        mounted &&
        identity.isCurrent &&
        target.oid == widget.oid &&
        target.replyType == widget.replyType &&
        target.root == widget.root &&
        target.parent == widget.parent &&
        identical(target.replyItem, widget.replyItem);
    _publishing.value = true;
    try {
      for (final item in editController.items) {
        if (item.type != RichTextType.at) continue;
        final mid = int.tryParse(item.id ?? '');
        if (mid == null || mid <= 0) {
          throw const Error('提及信息不完整，请重新选择用户');
        }
        atNameToMid[item.rawText] = mid;
      }
      pictures ??= await uploadPictures(account: account);
      if (!isCurrent()) return;
      final result = await commentActions.publish(
        account: account,
        type: target.replyType,
        oid: target.oid,
        root: target.root,
        parent: target.parent,
        message: message,
        atNameToMid: atNameToMid,
        pictures: pictures,
        syncToDynamic: syncToDynamic,
      );
      if (!isCurrent()) return;
      if (result case Success(:final response)) {
        const equality = DeepCollectionEquality();
        hasPub =
            text == editController.text &&
            rawText == editController.rawText &&
            syncToDynamic == _syncToDynamic.value &&
            equality.equals(draft, getRichContent()) &&
            equality.equals(images, pictureDraft);
        try {
          target.onSuccess?.call(response);
        } catch (error, stackTrace) {
          logger.w(
            '评论发送后的页面更新失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        }
        if (mounted && hasPub && route?.isCurrent == true) {
          Navigator.of(context).pop(response);
        }
        SmartDialog.showToast(
          !hasPub
              ? '发送成功，已保留新草稿'
              : response == null
              ? '发送成功，请刷新评论列表查看'
              : '发送成功',
        );
      } else {
        result.toast();
      }
    } catch (error, stackTrace) {
      if (isCurrent()) {
        (error is Error
                ? error
                : Error('评论准备失败，请重试', cause: error, stackTrace: stackTrace))
            .toast();
      }
    } finally {
      if (mounted) _publishing.value = false;
    }
  }

  Widget get latexBtn => ValueListenableBuilder(
    valueListenable: _latexOn,
    builder: (context, latexOn, _) => ToolbarIconButton(
      onPressed: latexOn ? _unlatexify : _latexify,
      icon: const Icon(Icons.functions, size: 22),
      tooltip: '公式',
      selected: latexOn,
    ),
  );

  Future<void> _latexify() async {
    // value.text is the display space (\uFFFC per emote), the same space
    // _replaceBlocks applies deltas in; formula spans hold no items, so the
    // text there is byte-equivalent to rawText.
    final rawText = editController.value.text;
    if (rawText.trim().isEmpty) return;

    final (spans, warnings) = LatexToUnicode.convertSpans(rawText);
    if (spans.isEmpty) {
      SmartDialog.showToast(
        warnings.isEmpty
            ? '未发现用 \$ 括起的公式'
            : '公式未能识别：${warnings.join('、')}（已保留原文）',
      );
      return;
    }

    _replaceBlocks(spans, rawText);
    _latexOn.value = true;
    if (warnings.isNotEmpty) {
      SmartDialog.showToast(
        '无法识别：${warnings.join('、')}（已保留原文）',
      );
    }
  }

  void _unlatexify() {
    // id 'latex' marks blocks created by _latexify.
    final blocks = editController.items
        .where((e) => e.type == .latex)
        .toList(growable: false);
    if (blocks.isEmpty) {
      _latexOn.value = false;
      return;
    }
    for (final item in blocks.reversed) {
      final oldValue = editController.value;
      final delta = RichTextEditingDeltaReplacement(
        oldText: oldValue.text,
        replacementText: item.rawText,
        replacedRange: TextRange(
          start: item.range.start,
          end: item.range.end,
        ),
        selection: TextSelection.collapsed(
          offset: item.range.start + item.rawText.length,
        ),
        composing: TextRange.empty,
        type: RichTextType.text,
      );
      final newValue = delta.apply(oldValue);
      if (oldValue == newValue) continue;
      editController
        ..syncRichText(delta)
        ..value = newValue;
    }
    _latexOn.value = false;
  }

  /// Replaces each formula span with a locked common-type block: the
  /// rendered Unicode goes into the block text, the LaTeX source into its
  /// rawText, and id 'latex' marks the block for toggling back.
  void _replaceBlocks(
    List<({int start, int end, String converted})> spans,
    String rawText,
  ) {
    for (final span in spans.reversed) {
      final oldValue = editController.value;
      final source = rawText.substring(span.start, span.end);
      final delta = RichTextEditingDeltaReplacement(
        oldText: oldValue.text,
        replacementText: span.converted,
        replacedRange: TextRange(start: span.start, end: span.end),
        selection: TextSelection.collapsed(
          offset: span.start + span.converted.length,
        ),
        composing: TextRange.empty,
        type: RichTextType.latex,
        rawText: source,
      );
      final newValue = delta.apply(oldValue);
      if (oldValue == newValue) continue;
      editController
        ..syncRichText(delta)
        ..value = newValue;
    }
  }
}
