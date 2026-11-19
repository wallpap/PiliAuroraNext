import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart'
    show IMSettingType, Setting;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/messaging/providers.dart';
import 'package:pili_aurora_next/services/messaging/settings.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

final whisperSettingsProvider =
    NotifierProvider.family<
      WhisperSettingsNotifier,
      WhisperSettingsSnapshot,
      IMSettingType
    >(WhisperSettingsNotifier.new, isAutoDispose: true);

class WhisperSettingsNotifier extends Notifier<WhisperSettingsSnapshot> {
  WhisperSettingsNotifier(this.type);

  final IMSettingType type;
  late WhisperSettingsHandle _handle;

  @override
  WhisperSettingsSnapshot build() {
    final session = ref.watch(messagingSessionProvider);
    final handle = WhisperSettingsHandle(session: session, type: type);
    _handle = handle;
    void changed() => state = handle.state.value;
    handle.state.addListener(changed);
    ref.onDispose(() {
      handle.state.removeListener(changed);
      handle.dispose();
    });
    unawaited(handle.refresh());
    return handle.state.value;
  }

  Future<void> onReload() => _handle.refresh();

  Future<LoadingState<void>> setSetting(int key, Setting setting) =>
      _handle.setSetting(key, setting);

  void mergeSubSettings(int parentKey, Map<int, Setting> settings) =>
      _handle.mergeSubSettings(parentKey, settings);
}

enum MessageReminderKind { mentions, likes, replies }

final messageReminderProvider = Provider.autoDispose
    .family<LoadingState<MessageReminderOptions>, MessageReminderKind>(
      (ref, kind) {
        final provider = whisperSettingsProvider(
          switch (kind) {
            .mentions => IMSettingType.SETTING_TYPE_OLD_AT_ME,
            .likes => IMSettingType.SETTING_TYPE_OLD_RECEIVE_LIKE,
            .replies => IMSettingType.SETTING_TYPE_OLD_REPLY_ME,
          },
        );
        final snapshot = ref.watch(provider);
        final options = snapshot.loadingState;
        if (options case Error()) return options;
        final settings = options.dataOrNull;
        if (settings == null) return LoadingState.loading();
        final entry = settings.entries
            .where(
              (entry) =>
                  entry.value.hasSelect() && entry.value.select.item.isNotEmpty,
            )
            .firstOrNull;
        if (entry == null) return const Error('暂无可用的提醒设置');
        return Success(
          MessageReminderOptions._(
            snapshot.title,
            ref.read(provider.notifier)._handle,
            entry.key,
            entry.value,
          ),
        );
      },
    );

class MessageReminderOptions {
  MessageReminderOptions._(this.title, this._handle, this._key, Setting setting)
    : _setting = setting.deepCopy(),
      labels = List.unmodifiable(
        setting.select.item.map((option) => option.text),
      ),
      selectedIndex = setting.select.item.indexWhere(
        (option) => option.selected,
      );

  final String title;
  final List<String> labels;
  final int selectedIndex;
  final WhisperSettingsHandle _handle;
  final int _key;
  final Setting _setting;

  bool get isActive => _handle.session.isActive;

  Future<LoadingState<void>> select(int index) {
    if (!isActive) return Future.value(const Error('账号已切换'));
    final options = _setting.select.item;
    if (index < 0 || index >= options.length) {
      return Future.value(const Error('提醒设置不可用'));
    }
    if (options[index].selected) return Future.value(const Success(null));
    final desired = _setting.deepCopy();
    for (final (position, option) in desired.select.item.indexed) {
      option.selected = position == index;
    }
    return _handle.setSetting(_key, desired);
  }
}
