import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/dynamic_badge_mode.dart';
import 'package:pili_aurora_next/services/messaging/models/msg_unread_type.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

typedef MessageBadgePreferences = ({
  DynamicBadgeMode mode,
  Set<MsgUnReadType> types,
});

sealed class BadgePreferenceChange {
  const BadgePreferenceChange();
}

class DynamicBadgeModeChanged extends BadgePreferenceChange {
  const DynamicBadgeModeChanged(this.mode);

  final DynamicBadgeMode mode;
}

class MessageBadgeModeChanged extends BadgePreferenceChange {
  const MessageBadgeModeChanged(this.mode);

  final DynamicBadgeMode mode;
}

class MessageBadgeTypesChanged extends BadgePreferenceChange {
  const MessageBadgeTypesChanged(this.types);

  final Set<MsgUnReadType> types;
}

final badgePreferencesProvider = Provider((ref) {
  final preferences = BadgePreferences();
  ref.onDispose(() => unawaited(preferences.close()));
  return preferences;
});

final class BadgePreferences {
  final _changes = StreamController<BadgePreferenceChange>.broadcast();
  Stream<BadgePreferenceChange> get changes => _changes.stream;

  static DynamicBadgeMode _readMode(String key) =>
      switch (GStorage.setting.get(key)) {
        int index when index >= 0 && index < DynamicBadgeMode.values.length =>
          DynamicBadgeMode.values[index],
        _ => DynamicBadgeMode.number,
      };

  DynamicBadgeMode get dynamicMode => _readMode(SettingBoxKey.dynamicBadgeMode);
  DynamicBadgeMode get messageMode => _readMode(SettingBoxKey.msgBadgeMode);

  Set<MsgUnReadType> get messageTypes {
    final saved = GStorage.setting.get(SettingBoxKey.msgUnReadTypeV2);
    return Set.unmodifiable(
      saved is List
          ? saved
                .whereType<int>()
                .where(
                  (index) => index >= 0 && index < MsgUnReadType.values.length,
                )
                .map((index) => MsgUnReadType.values[index])
          : MsgUnReadType.values,
    );
  }

  Future<void> saveDynamicMode(DynamicBadgeMode mode) async {
    await GStorage.setting.put(SettingBoxKey.dynamicBadgeMode, mode.index);
    _emit(DynamicBadgeModeChanged(mode));
  }

  Future<void> saveMessageMode(DynamicBadgeMode mode) async {
    await GStorage.setting.put(SettingBoxKey.msgBadgeMode, mode.index);
    _emit(MessageBadgeModeChanged(mode));
  }

  Future<void> saveMessageTypes(Set<MsgUnReadType> types) async {
    final selection = Set<MsgUnReadType>.unmodifiable(
      types.toList()
        ..sort((first, second) => first.index.compareTo(second.index)),
    );
    await GStorage.setting.put(
      SettingBoxKey.msgUnReadTypeV2,
      selection.map((type) => type.index).toList(),
    );
    _emit(MessageBadgeTypesChanged(selection));
  }

  void _emit(BadgePreferenceChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  Future<void> close() => _changes.close();
}
