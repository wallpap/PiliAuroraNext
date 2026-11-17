import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/time_picker.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/reserve_editor.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/domain/reserve_draft.dart';
import 'package:pili_aurora_next/utils/date_utils.dart';
import 'package:flutter/services.dart'
    show TextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart' hide showTimePicker;
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';

class CreateReservePage extends ConsumerStatefulWidget {
  const CreateReservePage({super.key, this.sid});

  final int? sid;

  @override
  ConsumerState<CreateReservePage> createState() => _CreateReservePageState();
}

class _CreateReservePageState extends ConsumerState<CreateReservePage> {
  final _owner = Object();
  ReserveEditorQuery get _query => (owner: _owner, id: widget.sid);
  ReserveEditor get _controller =>
      ref.read(reserveEditorProvider(_query).notifier);
  DraftEditorState<ReserveDraft> get _state =>
      ref.read(reserveEditorProvider(_query));
  ReserveDraft get _draft => _state.draft;
  late TextStyle _leadingStyle;

  Future<void> _onCreate() async {
    final route = ModalRoute.of(context);
    final query = _query;
    final editor = _controller;
    final draft = editor.draft;
    final result = await editor.onCreate();
    if (!mounted || query != _query || !editor.isCurrent) return;
    if (result case Success(:final response)) {
      if (draft == editor.draft && route?.isCurrent == true) {
        Navigator.of(context).pop(response);
      } else {
        SmartDialog.showToast('预约已保存，已保留当前草稿');
      }
    } else {
      result.toast();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reserveEditorProvider(_query));
    final theme = Theme.of(context);
    _leadingStyle = TextStyle(
      fontSize: 15,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
    );
    final padding = MediaQuery.viewPaddingOf(context);
    final divider = [
      const SizedBox(height: 10),
      Divider(
        height: 1,
        color: theme.colorScheme.outline.withValues(alpha: 0.1),
      ),
      const SizedBox(height: 10),
    ];
    return SimpleScaffold(
      appBar: AppBar(title: const Text('添加直播预约')),
      body: ListView(
        padding: EdgeInsets.only(
          top: 16,
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
          Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 65,
                child: Text('类型', style: _leadingStyle),
              ),
              Builder(
                builder: (_) => PopupMenuButton(
                  requestFocus: false,
                  initialValue: _draft.subType,
                  onSelected: (int value) =>
                      _controller.update((draft) => draft.copy(subType: value)),
                  itemBuilder: (context) {
                    return const [
                      AppPopupMenuItem(
                        value: 0,
                        child: Text('公开直播'),
                      ),
                      AppPopupMenuItem(
                        value: 1,
                        child: Text('大航海直播'),
                      ),
                    ];
                  },
                  child: Text(
                    _draft.subType == 0 ? '公开直播' : '大航海直播',
                  ),
                ),
              ),
            ],
          ),
          ...divider,
          Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 65,
                child: Text('时间', style: _leadingStyle),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    FocusManager.instance.primaryFocus?.unfocus();
                    DateTime? newDate = await showDatePicker(
                      context: context,
                      initialDate: _draft.date,
                      firstDate: _controller.now,
                      lastDate: _controller.end,
                    );
                    if (newDate != null && context.mounted) {
                      TimeOfDay? newTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(
                          _draft.date,
                        ),
                      );
                      if (newTime != null && mounted && _controller.isCurrent) {
                        final newEndtime = DateTime(
                          newDate.year,
                          newDate.month,
                          newDate.day,
                          newTime.hour,
                          newTime.minute,
                        );
                        if (newEndtime.difference(DateTime.now()) >=
                            const Duration(minutes: 5)) {
                          _controller.update(
                            (draft) => draft.copy(date: newEndtime),
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
                          _draft.date,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ...divider,
          Builder(
            builder: (_) => _buildInput(
              theme,
              key: ObjectKey(_state.inputKey),
              initialValue: _draft.title,
              onChanged: (value) =>
                  _controller.update((draft) => draft.copy(title: value)),
              desc: '标题',
              hintText: '请填写标题，最多14字',
              inputFormatters: [LengthLimitingTextInputFormatter(14)],
            ),
          ),
          ...divider,
          const SizedBox(height: 25),
          Builder(
            builder: (_) {
              return FilledButton.tonal(
                onPressed: _controller.canCreate && !_state.saving
                    ? _onCreate
                    : null,
                child: Text(_state.saving ? '保存中' : '添加预约'),
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
      ],
    );
  }
}
