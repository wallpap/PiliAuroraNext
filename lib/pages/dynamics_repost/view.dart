import 'dart:async';

import 'package:pili_aurora_next/common/widgets/animated_height.dart';
import 'package:pili_aurora_next/common/widgets/draggable_sheet/dyn.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/text_field.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformClampingPhysics;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_publishing.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/pages/common/publish/common_rich_text_pub_page.dart';
import 'package:pili_aurora_next/pages/emote/view.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:collection/collection.dart';
import 'package:pili_aurora_next/utils/request_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart' hide TextField;

class RepostPanel extends CommonRichTextPubPage {
  const RepostPanel({
    super.key,
    this.item,
    this.dynIdStr,
    this.onSuccess,
    // video
    this.rid,
    this.dynType,
    this.pic,
    this.title,
    this.uname,
    super.autofocus = false,
  });

  // video
  final int? rid;
  final int? dynType;
  final String? pic;
  final String? title;
  final String? uname;

  final DynamicItemModel? item;
  final String? dynIdStr;
  final VoidCallback? onSuccess;

  @override
  State<RepostPanel> createState() => _RepostPanelState();
}

class _RepostPanelState extends CommonRichTextPubPageState<RepostPanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final _publishing = ValueNotifier(false);

  @override
  void dispose() {
    _publishing.dispose();
    super.dispose();
  }

  late final String? _pic;
  late final String _text;
  late final String? _uname;

  static const _durtion = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    late final modules = widget.item?.modules;
    late final moduleDynamic = modules?.moduleDynamic;
    late final major = moduleDynamic?.major;

    _pic =
        widget.pic ??
        major?.archive?.cover ??
        major?.pgc?.cover ??
        major?.opus?.pics?.firstOrNull?.url;

    _text =
        widget.title ??
        major?.opus?.summary?.text ??
        major?.archive?.title ??
        major?.pgc?.title ??
        moduleDynamic?.desc?.text ??
        '';

    _uname = widget.uname ?? modules?.moduleAuthor?.name;
  }

  @override
  Widget build(BuildContext context) {
    Widget page([ScrollController? scrollController]) => Column(
      crossAxisAlignment: .start,
      mainAxisSize: _expanded ? .max : .min,
      children: [
        if (!_expanded) const SizedBox(height: 10),
        _buildAppBar(),
        if (_expanded) ...[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              controller: scrollController,
              physics: platformClampingPhysics,
              children: _buildEditPanel(),
            ),
          ),
          _buildToolbar,
          buildPanelContainer(Colors.transparent),
        ] else ...[
          ..._buildEditPanel(),
          ..._buildDismiss(),
        ],
      ],
    );

    return AnimatedHeight(
      vsync: this,
      expand: _expanded,
      curve: Curves.ease,
      duration: _durtion,
      child: _expanded
          ? DynDraggableScrollableSheet(
              snap: true,
              expand: false,
              minChildSize: 0,
              maxChildSize: 1,
              initialChildSize: 1,
              snapSizes: const [1],
              builder: (context, scrollController) => page(scrollController),
            )
          : page(),
    );
  }

  List<Widget> _buildEditPanel() => [
    Padding(
      padding: const .symmetric(horizontal: 16),
      child: _expanded
          ? _buildEditWidget()
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              child: _buildEditPlaceHolder(),
            ),
    ),
    const SizedBox(height: 10),
    _buildRefWidget(),
  ];

  Widget _buildRefWidget() => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          if (_pic != null) ...[
            NetworkImgLayer(
              width: 40,
              height: 40,
              src: _pic,
              borderRadius: const BorderRadius.all(
                Radius.circular(6),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_uname?.isNotEmpty == true)
                  Text(
                    '@$_uname',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                Text(
                  _text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEditPlaceHolder() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      setState(() => _expanded = true);
      Timer(_durtion, () {
        if (mounted) {
          focusNode.requestFocus();
        }
      });
    },
    child: SizedBox(
      width: double.infinity,
      child: Text(
        '说点什么吧',
        style: TextStyle(
          height: 1.75,
          fontSize: 15,
          color: theme.colorScheme.outline,
        ),
      ),
    ),
  );

  Widget _buildEditWidget() => ValueListenableBuilder(
    valueListenable: readOnly,
    builder: (context, readOnly, _) => RichTextField(
      key: key,
      controller: editController,
      minLines: 4,
      maxLines: null,
      autofocus: false,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      readOnly: readOnly,
      decoration: InputDecoration(
        hintText: '说点什么吧',
        hintStyle: TextStyle(color: theme.colorScheme.outline),
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          gapPadding: 0,
        ),
        contentPadding: EdgeInsets.zero,
      ),
      // inputFormatters: [LengthLimitingTextInputFormatter(1000)],
    ),
  );

  Widget _buildAppBar() => ListenableBuilder(
    listenable: _publishing,
    builder: (context, _) => !_expanded
        ? Row(
            children: [
              const SizedBox(width: 16),
              Text(
                widget.rid != null ? '分享至动态' : '转发动态',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: _publishing.value ? null : onPublishThrottle,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  _publishing.value
                      ? '发布中'
                      : widget.rid != null
                      ? '立即发布'
                      : '立即转发',
                ),
              ),
              const SizedBox(width: 16),
            ],
          )
        : Container(
            height: 66,
            padding: const EdgeInsets.all(16),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回',
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        backgroundColor: WidgetStatePropertyAll(
                          theme.colorScheme.secondaryContainer,
                        ),
                      ),
                      onPressed: Get.back,
                      icon: Icon(
                        Icons.arrow_back_outlined,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    widget.rid != null ? '分享至动态' : '转发动态',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _publishing.value ? null : onPublishThrottle,
                    style: FilledButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      _publishing.value
                          ? '发布中'
                          : widget.rid != null
                          ? '发布'
                          : '转发',
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget get _buildToolbar => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      spacing: 16,
      children: [
        emojiBtn,
        atBtn,
      ],
    ),
  );

  List<Widget> _buildDismiss() => [
    const SizedBox(height: 10),
    Divider(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    ),
    ListTile(
      dense: true,
      onTap: Get.back,
      title: Center(
        child: Text(
          '取消',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      ),
    ),
    SizedBox(height: 10 + MediaQuery.viewPaddingOf(context).bottom),
  ];

  @override
  Widget? get customPanel => EmotePanel(onChoose: onChooseEmote);

  List<Map<String, dynamic>>? getRepostContent(DynamicItemModel item) {
    try {
      return [
        {"raw_text": "//", "type": 1, "biz_id": ""},
        {
          "raw_text": "@${item.modules.moduleAuthor!.name}",
          "type": 2,
          "biz_id": item.modules.moduleAuthor!.mid.toString(),
        },
        {"raw_text": ":", "type": 1, "biz_id": ""},
        ...item.modules.moduleDynamic!.desc!.richTextNodes!.map(
          (e) {
            int type;
            String bizId;
            switch (e.type) {
              case 'RICH_TEXT_NODE_TYPE_EMOJI':
                type = 9;
                bizId = '';
              case 'RICH_TEXT_NODE_TYPE_AT':
                type = 2;
                bizId = e.rid ?? '';
              case 'RICH_TEXT_NODE_TYPE_TEXT':
              default:
                type = 1;
                bizId = '';
            }
            return {
              "raw_text": e.origText,
              "type": type,
              "biz_id": bizId,
            };
          },
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> onPublish() => onCustomPublish();

  @override
  Future<void> onCustomPublish({List? pictures}) async {
    if (!mounted || _publishing.value) return;
    final identity = AccountScope.capture();
    final account = identity.account;
    final item = widget.item;
    final dynIdStr = item?.idStr ?? widget.dynIdStr;
    final rid = widget.rid;
    final dynType = widget.dynType;
    final onSuccess = widget.onSuccess;
    final route = ModalRoute.of(context);
    final text = editController.text;
    final rawText = editController.rawText;
    final draft = getRichContent();
    final repostContent = item?.orig != null ? getRepostContent(item!) : null;
    final extraContent = draft == null
        ? repostContent
        : [...draft, ...?repostContent];
    final images = pictureDraft;
    final publishing = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(dynamicsPublishingProvider);
    bool isCurrent() =>
        mounted &&
        identity.isCurrent &&
        identical(item, widget.item) &&
        rid == widget.rid &&
        dynIdStr == (widget.item?.idStr ?? widget.dynIdStr) &&
        dynType == widget.dynType;
    _publishing.value = true;
    feedBack();
    try {
      final result = await publishing.submit(
        account,
        DynamicDraft(
          repostId: dynIdStr,
          videoId: rid,
          videoType: dynType,
          rawText: draft == null ? text : null,
          richText: extraContent,
        ),
        preparePictures: () async =>
            pictures ?? await uploadPictures(account: account),
        canSubmit: isCurrent,
      );
      if (!isCurrent() || result == null) return;
      if (result case Success(:final response)) {
        const equality = DeepCollectionEquality();
        hasPub =
            text == editController.text &&
            rawText == editController.rawText &&
            equality.equals(draft, getRichContent()) &&
            equality.equals(images, pictureDraft);
        if (mounted && hasPub && route?.isCurrent == true) {
          Navigator.of(context).pop();
        }
        SmartDialog.showToast(hasPub ? '转发成功' : '转发成功，已保留新草稿');
        try {
          onSuccess?.call();
        } catch (error, stackTrace) {
          logger.w(
            '动态转发后的页面更新失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        }
        if (response != null) {
          unawaited(
            RequestUtils.checkCreatedDyn(
              id: response,
              dynText: rawText,
              account: account,
            ),
          );
        }
      } else {
        result.toast();
      }
    } catch (error, stackTrace) {
      if (isCurrent()) {
        (error is Error
                ? error
                : Error('转发准备失败，请重试', cause: error, stackTrace: stackTrace))
            .toast();
      }
    } finally {
      if (mounted) _publishing.value = false;
    }
  }

  @override
  void onSave() {}
}
