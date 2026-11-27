import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:pili_aurora_next/pages/video/share_card/content.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

final class VideoShareCardPainter extends CustomPainter {
  const VideoShareCardPainter({
    required this.content,
    required this.code,
    this.cover,
    this.avatar,
    this.artwork,
    this.followers,
  });

  static const posterSize = Size(460, 520);

  final VideoShareCardContent content;
  final QrImage code;
  final ui.Image? cover;
  final ui.Image? avatar;
  final ui.Image? artwork;
  final int? followers;

  static QrImage qrImage(String url) => QrImage(
    QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.M),
  );

  @override
  void paint(Canvas canvas, Size size) {
    _CardCanvas(canvas, this).paint();
  }

  Future<Uint8List> png() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    paint(canvas, posterSize);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        (posterSize.width * 2).round(),
        (posterSize.height * 2).round(),
      );
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('分享卡片未能编码为 PNG');
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  @override
  bool shouldRepaint(VideoShareCardPainter oldDelegate) =>
      content != oldDelegate.content ||
      code != oldDelegate.code ||
      cover != oldDelegate.cover ||
      avatar != oldDelegate.avatar ||
      artwork != oldDelegate.artwork ||
      followers != oldDelegate.followers;
}

final class _CardCanvas {
  _CardCanvas(this.canvas, this.painter);

  static const _night = Color(0xff151d37);
  static const _mist = Color(0xffaebbd7);
  static const _white = Color(0xffffffff);
  static const _light = Color(0xfff0f3ff);
  static const _clear = Color(0x00000000);
  static final _titleShade = _verticalGradient(
    _night,
    (position) =>
        .30 * _smoothStep(.42, .71, position) +
        .70 * _smoothStep(.58, 1, position),
  );
  static final _coverFade = _verticalGradient(
    _white,
    (position) => 1 - _smoothStep(0, 1, position),
  );
  static final _titleBreak = RegExp(r'^(.{1,16}?[！!？?。])\s*(\S.+)$');

  static double _smoothStep(double start, double end, double position) {
    final progress = ((position - start) / (end - start)).clamp(0.0, 1.0);
    return progress * progress * (3 - 2 * progress);
  }

  static LinearGradient _verticalGradient(
    Color color,
    double Function(double position) opacity,
  ) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      for (var sample = 0; sample <= 32; sample++)
        color.withValues(alpha: opacity(sample / 32)),
    ],
  );

  final Canvas canvas;
  final VideoShareCardPainter painter;

  VideoShareCardContent get content => painter.content;
  String get _authorMetadata => content.authorMetadata(painter.followers);

  (String, String) get _headline {
    final headline = content.headline;
    if (content.subtitle.isNotEmpty) return (headline, content.subtitle);
    final match = _titleBreak.firstMatch(headline);
    if (content.author != null && match != null) {
      return (match[1]!, match[2]!);
    }
    return (headline, '');
  }

  void paint() {
    _posterCover();
    final duration = content.duration;
    if (content.author != null) {
      _author(358, width: duration.isEmpty ? 412 : 310);
    } else {
      _text(content.publication, 24, 365, 300, 15, _mist);
    }
    if (duration.isNotEmpty) {
      _text('时长 $duration', 322, 365, 114, 14, _mist, align: TextAlign.right);
    }
    _fill(24, 406, 412, 1, const Color(0x26ffffff));
    _text(content.metrics, 24, 430, 300, 14, const Color(0xffb9c5df));
    _text(
      content.watchLabel,
      24,
      content.metrics.isEmpty ? 444 : 456,
      300,
      19,
      _light,
      bold: true,
    );
    _qr(348, 416, 88);
  }

  void _posterCover() {
    const size = VideoShareCardPainter.posterSize;
    _fill(0, 0, size.width, size.height, _night);
    const header = Rect.fromLTWH(0, 0, 460, 322);
    final cover = painter.cover ?? painter.artwork;
    final artwork = painter.cover == null ? null : painter.artwork;
    if (cover != null) {
      _coverBackdrop(cover, header);
      _coverForeground(
        cover,
        Rect.fromLTWH(0, 0, artwork == null ? header.width : 304, 262),
      );
    }
    canvas.drawRect(header, Paint()..shader = _titleShade.createShader(header));
    if (artwork != null) {
      paintImage(
        canvas: canvas,
        rect: const Rect.fromLTWH(314, 16, 122, 182),
        image: artwork,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    final (headline, subtitle) = _headline;
    const titleWidth = 412.0;
    const singleLineSize = 44.0;
    final singleLine =
        _textWidth(headline, singleLineSize, bold: true) <= titleWidth;
    _text(
      headline,
      24,
      singleLine ? 246 : 238,
      titleWidth,
      singleLine ? singleLineSize : 32,
      _white,
      bold: true,
      lines: singleLine ? 1 : 2,
    );
    _text(subtitle, 24, 316, 412, 26, const Color(0xffe2e8ff), bold: true);
  }

  void _author(double top, {required double width}) {
    final avatar = painter.avatar;
    if (avatar != null) {
      final rect = Rect.fromLTWH(24, top, 34, 34);
      canvas
        ..save()
        ..clipPath(Path()..addOval(rect));
      paintImage(
        canvas: canvas,
        rect: rect,
        image: avatar,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
    }
    final inset = avatar == null ? 0.0 : 44.0;
    _text(
      content.author!,
      24 + inset,
      top - 1,
      width - inset,
      16,
      _light,
      bold: true,
    );
    _text(_authorMetadata, 24 + inset, top + 20, width - inset, 13, _mist);
  }

  void _coverBackdrop(ui.Image image, Rect bounds) {
    canvas
      ..save()
      ..clipRect(bounds)
      ..saveLayer(
        bounds.inflate(48),
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      );
    paintImage(
      canvas: canvas,
      rect: bounds.inflate(48),
      image: image,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
    );
    canvas
      ..restore()
      ..restore();
  }

  void _coverForeground(ui.Image image, Rect bounds) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, bounds.size);
    final rect = Alignment.topCenter.inscribe(fitted.destination, bounds);
    final fadeLeft = rect.left > 0.5;
    final fadeRight = rect.right < VideoShareCardPainter.posterSize.width - 0.5;
    final fade = Rect.fromLTRB(
      rect.left,
      rect.bottom - (rect.height * .18).clamp(20.0, 48.0),
      rect.right,
      rect.bottom,
    );
    canvas
      ..saveLayer(rect, Paint())
      ..drawImageRect(
        image,
        Offset.zero & source,
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..drawRect(
        rect.inflate(1),
        Paint()
          ..isAntiAlias = false
          ..blendMode = BlendMode.dstIn
          ..shader = _coverFade.createShader(fade),
      );
    if (fadeLeft || fadeRight) {
      canvas.drawRect(
        rect.inflate(1),
        Paint()
          ..isAntiAlias = false
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            colors: [
              if (fadeLeft) _clear,
              _white,
              _white,
              if (fadeRight) _clear,
            ],
            stops: [if (fadeLeft) 0, .035, .965, if (fadeRight) 1],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  void _qr(double left, double top, double side) {
    final code = painter.code;
    final modules = code.moduleCount;
    final cell = (2 * side / (modules + 8)).floor() / 2;
    final inset = (side - (modules + 2) * cell).floorToDouble() / 2;
    final startX = left + inset + cell;
    final startY = top + inset + cell;
    final span = (modules + 2) * cell;
    _fill(left + inset, top + inset, span, span, _white);
    final paint = Paint()
      ..color = const Color(0xff000000)
      ..isAntiAlias = false;
    for (var row = 0; row < modules; row++) {
      for (var column = 0; column < modules; column++) {
        if (code.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTWH(
              startX + column * cell,
              startY + row * cell,
              cell,
              cell,
            ),
            paint,
          );
        }
      }
    }
  }

  void _fill(
    double left,
    double top,
    double width,
    double height,
    Color color,
  ) => canvas.drawRect(
    Rect.fromLTWH(left, top, width, height),
    Paint()..color = color,
  );

  double _textWidth(String value, double size, {required bool bold}) {
    final text = _textPainter(value, size, _white, bold)..layout();
    final width = text.width;
    text.dispose();
    return width;
  }

  void _text(
    String value,
    double left,
    double top,
    double width,
    double size,
    Color color, {
    bool bold = false,
    int lines = 1,
    TextAlign align = TextAlign.left,
  }) {
    if (value.isEmpty) return;
    _textPainter(value, size, color, bold)
      ..maxLines = lines
      ..ellipsis = '…'
      ..textAlign = align
      ..layout(minWidth: width, maxWidth: width)
      ..paint(canvas, Offset(left, top))
      ..dispose();
  }

  TextPainter _textPainter(String value, double size, Color color, bool bold) =>
      TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const [
              'Microsoft YaHei UI',
              'Roboto',
              'Noto Sans CJK SC',
            ],
            fontSize: size,
            height: 1.13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
}
