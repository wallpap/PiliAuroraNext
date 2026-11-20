import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/setting/widgets/select_dialog.dart';
import 'package:pili_aurora_next/services/messaging/providers.dart';
import 'package:pili_aurora_next/services/messaging/settings_providers.dart';

class MessageReminderButton extends ConsumerStatefulWidget {
  const MessageReminderButton({
    super.key,
    required this.type,
    required this.title,
    required this.icon,
  });

  final MessageReminderKind type;
  final String title;
  final Widget icon;

  @override
  ConsumerState<MessageReminderButton> createState() =>
      _MessageReminderButtonState();
}

class _MessageReminderButtonState extends ConsumerState<MessageReminderButton> {
  bool _opening = false;
  Completer<LoadingState<MessageReminderOptions>?>? _pending;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.title,
    onPressed: _opening ? null : _open,
    icon: widget.icon,
  );

  Future<void> _open() async {
    setState(() => _opening = true);
    final session = ref.read(messagingSessionProvider);
    final provider = messageReminderProvider(widget.type);
    final pending = _pending =
        Completer<LoadingState<MessageReminderOptions>?>();
    // 读取、选择和保存期间持有设置句柄，弹窗只接收已完成的结果。
    final subscription = ref.listenManual(provider, (_, snapshot) {
      if (snapshot is! Loading && !pending.isCompleted) {
        pending.complete(snapshot);
      }
    }, fireImmediately: true);
    try {
      final snapshot = await pending.future;
      if (!mounted ||
          snapshot == null ||
          !identical(session, ref.read(messagingSessionProvider))) {
        return;
      }
      final settings = snapshot.dataOrNull;
      if (settings == null) {
        snapshot.toast();
        return;
      }
      if (!settings.isActive) return;
      final selected = await showDialog<int>(
        context: context,
        builder: (_) => SelectDialog<int>(
          title: settings.title.isEmpty ? widget.title : settings.title,
          value: settings.selectedIndex,
          values: [
            for (final (index, label) in settings.labels.indexed)
              (index, label),
          ],
        ),
      );
      if (!mounted ||
          !settings.isActive ||
          selected == null ||
          selected == settings.selectedIndex) {
        return;
      }
      final result = await settings.select(selected);
      if (mounted && settings.isActive && !result.isSuccess) result.toast();
    } finally {
      subscription.close();
      _pending = null;
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    super.dispose();
  }
}
