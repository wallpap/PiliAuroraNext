import 'dart:ui' show Color;

import 'package:pili_aurora_next/features/sponsor_block/data/sponsor_block_preferences.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/skip_type.dart';

mixin BlockConfigMixin {
  static SkipType get defaultPgcSkipType => SponsorBlockPreferences.pgcSkipType;

  late final pgcSkipType = defaultPgcSkipType;
  late final enablePgcSkip = pgcSkipType != SkipType.disable;
  late final enableSponsorBlock = SponsorBlockPreferences.enabled;
  late final enableBlock = enableSponsorBlock || enablePgcSkip;
  late final _colors = SponsorBlockPreferences.colors;
  late final blockLimit = SponsorBlockPreferences.limit * 1000;
  late final blockSettings = SponsorBlockPreferences.behaviors;
  late final enableList = {
    for (final entry in blockSettings.entries)
      if (entry.value != SkipType.disable) entry.key.name,
  };

  Color segmentColor(SegmentType segment) => _colors[segment.index];
}
