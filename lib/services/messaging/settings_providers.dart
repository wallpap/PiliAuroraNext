import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/messaging/providers.dart';
import 'package:pili_aurora_next/services/messaging/settings.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';

final whisperSettingsProvider =
    NotifierProvider.family<
      WhisperSettingsNotifier,
      WhisperSettingsSnapshot,
      WhisperSettingsSection
    >(WhisperSettingsNotifier.new, isAutoDispose: true);

class WhisperSettingsNotifier extends Notifier<WhisperSettingsSnapshot> {
  WhisperSettingsNotifier(this.type);

  final WhisperSettingsSection type;
  late WhisperSettingsHandle handle;

  @override
  WhisperSettingsSnapshot build() {
    final session = ref.watch(messagingSessionProvider);
    final current = handle = WhisperSettingsHandle(
      session: session,
      type: type,
    );
    void changed() => state = current.state.value;
    current.state.addListener(changed);
    ref.onDispose(() {
      current.state.removeListener(changed);
      current.dispose();
    });
    scheduleMicrotask(() => unawaited(current.refresh()));
    return current.state.value;
  }
}

enum MessageReminderKind { mentions, likes, replies }

final messageReminderProvider = Provider.autoDispose
    .family<LoadingState<MessageReminderOptions>, MessageReminderKind>(
      (ref, kind) {
        final provider = whisperSettingsProvider(
          switch (kind) {
            .mentions => WhisperSettingsSection.mentions,
            .likes => WhisperSettingsSection.likes,
            .replies => WhisperSettingsSection.replies,
          },
        );
        final snapshot = ref.watch(provider);
        final options = snapshot.loadingState;
        if (options case Error()) return options;
        final settings = options.dataOrNull;
        if (settings == null) return LoadingState.loading();
        for (final entry in settings.entries) {
          if (entry.value case WhisperSettingChoices(:final options)
              when options.isNotEmpty) {
            return Success(
              MessageReminderOptions._(
                snapshot.title,
                ref.read(provider.notifier).handle,
                entry.key,
                options,
              ),
            );
          }
        }
        return const Error('暂无可用的提醒设置');
      },
    );

class MessageReminderOptions {
  MessageReminderOptions._(this.title, this._handle, this._key, this._options)
    : labels = List.unmodifiable(_options.map((option) => option.label)),
      selectedIndex = _options.indexWhere((option) => option.selected);

  final String title;
  final List<String> labels;
  final int selectedIndex;
  final WhisperSettingsHandle _handle;
  final int _key;
  final List<WhisperSettingOption> _options;

  bool get isActive => _handle.isActive;

  Future<LoadingState<void>> select(int index) async {
    if (!isActive) return const Error('账号已切换');
    if (index < 0 || index >= _options.length) {
      return const Error('提醒设置不可用');
    }
    final option = _options[index];
    if (option.selected) return const Success(null);
    final result = await _handle.edit(
      _key,
      SelectWhisperOption(index, option.label),
    );
    return switch (result) {
      Success() => const Success(null),
      Error() => result,
      Loading() => LoadingState.loading(),
    };
  }
}
