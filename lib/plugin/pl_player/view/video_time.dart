import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

class VideoTime extends LeafRenderObjectWidget {
  const VideoTime({
    super.key,
    required this.position,
    required this.duration,
  });

  final String position;
  final String duration;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderVideoTime(
    position: position,
    duration: duration,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderVideoTime)
      ..position = position
      ..duration = duration;
  }
}

class _RenderVideoTime extends RenderBox {
  _RenderVideoTime({
    required this._position,
    required this._duration,
  });

  String _duration;
  set duration(String value) {
    if (_duration == value) return;
    _duration = value;
    final paragraph = _buildParagraph(const Color(0xFFD0D0D0), _duration);
    if (paragraph.maxIntrinsicWidth != _cache?.maxIntrinsicWidth) {
      markNeedsLayout();
    }
    _cache?.dispose();
    _cache = paragraph;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  String _position;
  set position(String value) {
    if (_position == value) return;
    _position = value;
    _positionCache?.dispose();
    _positionCache = null;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ui.Paragraph? _cache;
  ui.Paragraph? _positionCache;

  static ui.Paragraph _buildParagraph(Color color, String time) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: 10,
              height: 1.4,
              fontFamily: 'Monospace',
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: 10,
              height: 1.4,
              fontFamily: 'Monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
          ..addText(time);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: .infinity));
  }

  @override
  ui.Size computeDryLayout(covariant BoxConstraints constraints) {
    final paragraph = _cache ??= _buildParagraph(
      const Color(0xFFD0D0D0),
      _duration,
    );
    return Size(paragraph.maxIntrinsicWidth, paragraph.height * 2);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..textDirection = .ltr
      ..label = 'position:$_position\nduration:$_duration';
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final para = _positionCache ??= _buildParagraph(Colors.white, _position);
    context.canvas
      ..drawParagraph(
        para,
        Offset(
          offset.dx + _cache!.maxIntrinsicWidth - para.maxIntrinsicWidth,
          offset.dy,
        ),
      )
      ..drawParagraph(_cache!, Offset(offset.dx, offset.dy + para.height));
  }

  @override
  void dispose() {
    _cache?.dispose();
    _cache = null;
    _positionCache?.dispose();
    _positionCache = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;
}
