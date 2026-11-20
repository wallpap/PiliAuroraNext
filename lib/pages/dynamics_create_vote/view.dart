import 'dart:io' show File;

import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/time_picker.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/vote_editor.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/domain/vote_draft.dart';
import 'package:pili_aurora_next/core/time/date_format.dart';
import 'package:pili_aurora_next/core/io/file_ext.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/core/async/rate_limiter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart' hide showTimePicker;
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';

class CreateVotePage extends ConsumerStatefulWidget {
  const CreateVotePage({super.key, this.voteId});

  final int? voteId;

  @override
  ConsumerState<CreateVotePage> createState() => _CreateVotePageState();
}

class _CreateVotePageState extends ConsumerState<CreateVotePage> {
  final _owner = Object();
  VoteEditorQuery get _query => (owner: _owner, id: widget.voteId);
  VoteEditor get _controller => ref.read(voteEditorProvider(_query).notifier);
  DraftEditorState<VoteDraft> get _state =>
      ref.read(voteEditorProvider(_query));
  VoteDraft get _draft => _state.draft;
  late final imagePicker = ImagePicker();

  late TextStyle _leadingStyle;

  Future<void> _onCreate() async {
    final route = ModalRoute.of(context);
    final query = _query;
    final editor = _controller;
    final draft = editor.draft;
    final result = await editor.onCreate();
    if (!mounted || query != _query || !editor.isCurrent) return;
    if (result case Success(:final response)) {
      if (listEquals(draft, editor.draft) && route?.isCurrent == true) {
        Navigator.of(context).pop(response);
      } else {
        SmartDialog.showToast('投票已保存，已保留当前草稿');
      }
    } else {
      result.toast();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(voteEditorProvider(_query));
    final theme = Theme.of(context);
    _leadingStyle = TextStyle(
      fontSize: 15,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
    );
    final padding = MediaQuery.viewPaddingOf(context);
    final divider = Divider(
      height: 20,
      thickness: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );
    return SimpleScaffold(
      appBar: AppBar(
        title: Text('${_controller.voteId != null ? '' : '发起'}投票'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: padding.left + 16,
          right: padding.right + 16,
          bottom: padding.bottom + 100,
        ),
        children: [
          Builder(
            builder: (_) {
              if (_state.loading) {
                return const LinearProgressIndicator();
              }
              final error = _state.error;
              return error == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      title: Text(error.toString()),
                      trailing: TextButton(
                        onPressed: _controller.queryData,
                        child: const Text('重试'),
                      ),
                    );
            },
          ),
          const Text(
            '投票类型',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          _buildType(theme),
          const SizedBox(height: 40),
          Builder(
            builder: (_) => _buildInput(
              theme,
              key: ValueKey((_state.inputKey, 'title')),
              initialValue: _draft.title,
              onChanged: (value) =>
                  _controller.update((draft) => draft.copy(title: value)),
              desc: '投票标题',
              hintText: '请填写标题',
              inputFormatters: [LengthLimitingTextInputFormatter(32)],
            ),
          ),
          divider,
          Builder(
            builder: (_) => _buildInput(
              theme,
              key: ValueKey((_state.inputKey, 'desc')),
              initialValue: _draft.description,
              onChanged: (value) =>
                  _controller.update((draft) => draft.copy(description: value)),
              desc: '投票说明',
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
            ),
          ),
          divider,
          const SizedBox(height: 40),
          Builder(
            builder: (_) {
              final showImg = _draft.type == 1;
              final showDel = _draft.options.length > 2;
              List<Widget> children = [];
              for (int i = 0; i < _draft.options.length; i++) {
                final e = _draft.options[i];
                children
                  ..add(
                    _buildInput(
                      theme,
                      key: ObjectKey(e.id),
                      showDel: showDel,
                      onDel: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _controller.onDel(i);
                      },
                      showImg: showImg,
                      imgUrl: e.image,
                      onPickImg: () => ActionThrottle.run(
                        'picImg',
                        const Duration(milliseconds: 500),
                        () => _onPickImg(i),
                      ),
                      initialValue: e.text,
                      onChanged: (value) => _controller.optionText(e.id, value),
                      desc: '选项${i + 1}',
                      hintText: '选项内容，最多20字',
                      inputFormatters: [LengthLimitingTextInputFormatter(20)],
                    ),
                  )
                  ..add(divider);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...children,
                  if (_draft.options.length < 20)
                    FilledButton(
                      onPressed: _controller.addOption,
                      style: FilledButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.only(
                          left: 10,
                          right: 14,
                          top: 4,
                          bottom: 4,
                        ),
                        visualDensity: .standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        backgroundColor: theme.colorScheme.onInverseSurface,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16),
                          Text(
                            ' 添加选项',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
          Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 100,
                child: Text('单选/多选', style: _leadingStyle),
              ),
              Builder(
                builder: (_) {
                  final choiceCnt = _draft.choices;
                  final choices = List.generate(
                    _draft.options.length,
                    (i) => i + 1,
                  );
                  return Listener(
                    onPointerDown: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    child: PopupMenuButton<int>(
                      initialValue: choiceCnt,
                      requestFocus: false,
                      onSelected: (value) => _controller.update(
                        (draft) => draft.copy(choices: value),
                      ),
                      itemBuilder: (context) {
                        return choices
                            .map(
                              (e) => AppPopupMenuItem(
                                value: e,
                                child: Text(e == 1 ? '单选' : '最多选$e项'),
                              ),
                            )
                            .toList();
                      },
                      child: Text(
                        choiceCnt == 1 ? '单选         ' : '最多选$choiceCnt项',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          divider,
          Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 100,
                child: Text('投票截止时间', style: _leadingStyle),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final query = _query;
                  final editor = _controller;
                  final initialDate = _draft.deadline;
                  FocusManager.instance.primaryFocus?.unfocus();
                  DateTime? newDate = await showDatePicker(
                    context: context,
                    initialDate: initialDate,
                    firstDate: editor.now,
                    lastDate: editor.end,
                  );
                  if (newDate != null &&
                      context.mounted &&
                      query == _query &&
                      editor.isCurrent) {
                    TimeOfDay? newTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(initialDate),
                    );
                    if (newTime != null &&
                        mounted &&
                        query == _query &&
                        editor.isCurrent) {
                      final newEndtime = DateTime(
                        newDate.year,
                        newDate.month,
                        newDate.day,
                        newTime.hour,
                        newTime.minute,
                      );
                      if (newEndtime.difference(DateTime.now()) >=
                          const Duration(minutes: 5)) {
                        editor.update(
                          (draft) => draft.copy(deadline: newEndtime),
                        );
                      } else {
                        SmartDialog.showToast('至少选择5分钟之后');
                      }
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Builder(
                    builder: (_) => Text(
                      DateFormatUtils.longFormatD.format(
                        _draft.deadline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          divider,
          const SizedBox(height: 40),
          Builder(
            builder: (_) {
              final canCreate = _controller.canCreate;
              return FilledButton.tonal(
                onPressed: canCreate && !_state.saving ? _onCreate : null,
                child: Text(_state.saving ? '保存中' : '发起投票'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInput(
    ThemeData theme, {
    Key? key,
    String? initialValue,
    required ValueChanged<String> onChanged,
    required String desc,
    String? hintText,
    List<TextInputFormatter>? inputFormatters,
    bool showDel = false,
    bool showImg = false,
    String? imgUrl,
    VoidCallback? onDel,
    VoidCallback? onPickImg,
  }) {
    return Row(
      spacing: 12,
      children: [
        SizedBox(
          width: 65,
          child: Text(
            desc,
            style: _leadingStyle,
          ),
        ),
        Expanded(
          child: TextFormField(
            key: key,
            initialValue: initialValue,
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hintText ?? desc,
              hintStyle: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
            inputFormatters: inputFormatters,
          ),
        ),
        if (showImg)
          GestureDetector(
            onTap: onPickImg,
            child: NetworkImgLayer(
              src: imgUrl,
              width: 40,
              height: 40,
              borderRadius: const BorderRadius.all(
                Radius.circular(6),
              ),
            ),
          ),
        if (showDel)
          iconButton(
            size: 26,
            iconSize: 18,
            tooltip: '移除',
            icon: const Icon(Icons.clear),
            onPressed: onDel,
            iconColor: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _buildType(ThemeData theme) => Builder(
    builder: (_) {
      return Row(
        spacing: 16,
        children: List.generate(
          2,
          (index) {
            final isEnable = index == _draft.type;
            final style = TextButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isEnable
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.outline,
                ),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              backgroundColor: isEnable
                  ? theme.colorScheme.secondaryContainer
                  : Colors.transparent,
              foregroundColor: isEnable
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            );
            Widget child = TextButton(
              style: style,
              onPressed: () =>
                  _controller.update((draft) => draft.copy(type: index)),
              child: Text(
                '${const ['文字', '图片'][index]}投票',
                style: const TextStyle(fontSize: 14, height: 1),
                strutStyle: const StrutStyle(
                  height: 1,
                  leading: 0,
                  fontSize: 14,
                ),
              ),
            );
            if (isEnable) {
              child = Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomRight: Radius.circular(6),
                        ),
                        color: theme.colorScheme.primary,
                      ),
                      child: Icon(
                        size: 10,
                        Icons.check,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              );
            }
            return child;
          },
        ),
      );
    },
  );

  void _onPickImg(int index) {
    final option = _draft.options[index];
    final query = _query;
    final editor = _controller;
    ActionThrottle.run(
      'imagePicker',
      const Duration(milliseconds: 500),
      () async {
        try {
          final pickedFile = await imagePicker.pickImage(
            imageQuality: 100,
            source: ImageSource.gallery,
            requestFullMetadata: false,
          );
          if (pickedFile != null) {
            final path = pickedFile.path;
            try {
              if (!mounted || query != _query || !editor.isCurrent) return;
              final result = await editor.onUpload(option.id, path);
              if (mounted &&
                  query == _query &&
                  editor.isCurrent &&
                  !result.isSuccess) {
                result.toast();
              }
            } finally {
              if (PlatformUtils.isMobile) File(path).tryDel();
            }
          }
        } catch (e) {
          if (mounted) SmartDialog.showToast(e.toString());
        }
      },
    );
  }
}
