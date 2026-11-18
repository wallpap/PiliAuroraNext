import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';

const _family = 'PiliAuroraNextIcons';
const _icons = <String, IconData>{
  'ai_circle': CustomIcons.ai_circle,
  'dm_off': CustomIcons.dm_off,
  'dm_on': CustomIcons.dm_on,
  'dm_settings': CustomIcons.dm_settings,
  'flip_rotate_90': CustomIcons.flip_rotate_90,
  'folderDownloadOutline': CustomIcons.folderDownloadOutline,
  'history': CustomIcons.history,
  'identifier_circle': CustomIcons.identifier_circle,
  'live_reserve': CustomIcons.live_reserve,
  'motion_photos_on': CustomIcons.motion_photos_on,
  'motion_photos_on_outlined': CustomIcons.motion_photos_on_outlined,
  'open_in_full_rotate_45': CustomIcons.open_in_full_rotate_45,
  'player_dm_tip_back': CustomIcons.player_dm_tip_back,
  'player_dm_tip_copy': CustomIcons.player_dm_tip_copy,
  'player_dm_tip_like': CustomIcons.player_dm_tip_like,
  'player_dm_tip_like_solid': CustomIcons.player_dm_tip_like_solid,
  'player_dm_tip_recall': CustomIcons.player_dm_tip_recall,
  'repeat_rounded_rotate_90': CustomIcons.repeat_rounded_rotate_90,
  'replay_rounded': CustomIcons.replay_rounded,
  'share_node': CustomIcons.share_node,
  'shield_play_arrow': CustomIcons.shield_play_arrow,
  'shield_published': CustomIcons.shield_published,
  'shield_reply': CustomIcons.shield_reply,
  'shopping_bag_not_interested': CustomIcons.shopping_bag_not_interested,
  'splitscreen_rotate_90': CustomIcons.splitscreen_rotate_90,
  'star_favorite_line': CustomIcons.star_favorite_line,
  'star_favorite_solid': CustomIcons.star_favorite_solid,
  'subscriptions_outlined': CustomIcons.subscriptions_outlined,
  'topic_tag': CustomIcons.topic_tag,
  'touch_app_rotate_270': CustomIcons.touch_app_rotate_270,
  'view_headline_rotate_90': CustomIcons.view_headline_rotate_90,
  'watch_later_outlined': CustomIcons.watch_later_outlined,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(_family)
          ..addFont(rootBundle.load('assets/fonts/piliauroranext_icons.ttf')))
        .load();
  });

  test('发布字形可绘制，且各图标不共用缺字或重复轮廓', () async {
    final missingGlyph = await _pixels(0xf8ff);
    final shapes = <List<int>>[];
    for (final entry in _icons.entries) {
      final icon = entry.value;
      expect(icon.fontFamily, _family, reason: entry.key);
      expect(
        icon.codePoint,
        inInclusiveRange(0xe000, 0xf8ff),
        reason: entry.key,
      );
      final pixels = await _pixels(icon.codePoint);
      expect(pixels.any((alpha) => alpha != 0), isTrue, reason: entry.key);
      expect(pixels, isNot(orderedEquals(missingGlyph)), reason: entry.key);
      expect(shapes, isNot(contains(orderedEquals(pixels))), reason: entry.key);
      shapes.add(pixels);
    }
  });
}

Future<List<int>> _pixels(int codePoint) async {
  final recorder = ui.PictureRecorder();
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(codePoint),
      style: const TextStyle(
        fontFamily: _family,
        fontSize: 96,
        color: Color(0xff000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 96);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    return [for (var index = 3; index < bytes.length; index += 4) bytes[index]];
  } finally {
    image.dispose();
    picture.dispose();
    painter.dispose();
  }
}
