import 'dart:async' show unawaited;
import 'dart:ui' show Color;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:pili_aurora_next/common/service_urls.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/skip_type.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/utils.dart';

enum SponsorBlockPreference {
  limit(SettingBoxKey.blockLimit),
  behaviors(SettingBoxKey.blockSettings),
  colors(SettingBoxKey.blockColor),
  userId(SettingBoxKey.blockUserID),
  toast(SettingBoxKey.blockToast),
  server(SettingBoxKey.blockServer),
  track(SettingBoxKey.blockTrack);

  const SponsorBlockPreference(this._key);
  final String _key;
}

abstract final class SponsorBlockPreferences {
  static const defaultServer = HttpString.sponsorBlockBaseUrl;
  static const _legacyCategories = [
    'sponsor',
    'selfpromo',
    'exclusive_access',
    'interaction',
    'poi_highlight',
    'intro',
    'outro',
    'preview',
    'padding',
    'filler',
    'music_offtopic',
  ];

  static String get server => GStorage.setting.get(
    SettingBoxKey.blockServer,
    defaultValue: defaultServer,
  );

  static String get userId {
    final stored = GStorage.setting.get(SettingBoxKey.blockUserID);
    if (stored is String && stored.isNotEmpty) return stored;
    final generated = generateUserId();
    unawaited(
      save(SponsorBlockPreference.userId, generated).catchError(
        (Object error, StackTrace stackTrace) => logger.w(
          '空降助手用户 ID 保存失败',
          error: error.runtimeType,
          stackTrace: stackTrace,
        ),
      ),
    );
    return generated;
  }

  static bool get toast =>
      GStorage.setting.get(SettingBoxKey.blockToast, defaultValue: true);
  static bool get track =>
      GStorage.setting.get(SettingBoxKey.blockTrack, defaultValue: !kDebugMode);
  static double get limit =>
      GStorage.setting.get(SettingBoxKey.blockLimit, defaultValue: 0.0);
  static bool get enabled => GStorage.setting.get(
    SettingBoxKey.enableSponsorBlock,
    defaultValue: false,
  );
  static SkipType get pgcSkipType => _skipType(
    GStorage.setting.get(SettingBoxKey.pgcSkipType),
    SkipType.skipOnce,
  );

  static Object? _categoryValue(Object? stored, SegmentType category) {
    if (stored is Map) return stored[category.name];
    if (stored is List) {
      final index = stored.length == SegmentType.values.length
          ? category.index
          : _legacyCategories.indexOf(category.name);
      if (index >= 0 && index < stored.length) return stored[index];
    }
    return null;
  }

  static SkipType _skipType(Object? value, SkipType fallback) =>
      value is int && value >= 0 && value < SkipType.values.length
      ? SkipType.values[value]
      : fallback;

  static List<Color> get colors {
    final stored = GStorage.setting.get(SettingBoxKey.blockColor);
    return SegmentType.values.map((category) {
      final value = _categoryValue(stored, category);
      final color = value is String && value.length == 6
          ? int.tryParse('FF$value', radix: 16)
          : null;
      return color != null ? Color(color) : Color(category.colorValue);
    }).toList();
  }

  static Map<SegmentType, SkipType> get behaviors {
    final stored = GStorage.setting.get(SettingBoxKey.blockSettings);
    return {
      for (final category in SegmentType.values)
        category: _skipType(
          _categoryValue(stored, category),
          category == SegmentType.jumpscare
              ? stored == null
                    ? SkipType.alwaysSkip
                    : SkipType.disable
              : SkipType.skipOnce,
        ),
    };
  }

  static String generateUserId() =>
      Digest(List.generate(16, (_) => Utils.random.nextInt(256))).toString();

  static Future<void> save(SponsorBlockPreference field, Object value) async {
    final stored = switch (field) {
      SponsorBlockPreference.behaviors => {
        for (final entry in (value as Map<SegmentType, SkipType>).entries)
          entry.key.name: entry.value.index,
      },
      SponsorBlockPreference.colors => {
        for (final category in SegmentType.values)
          category.name: (value as List<Color>)[category.index]
              .toARGB32()
              .toRadixString(16)
              .padLeft(8, '0')
              .substring(2),
      },
      _ => value,
    };
    await GStorage.setting.put(field._key, stored);
  }
}
