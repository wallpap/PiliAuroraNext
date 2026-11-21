import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

class Skeleton extends StatefulWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final matrix = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(
        min: -0.5,
        max: 1.5,
        period: const Duration(seconds: 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAnimating) return widget.child;
    final color = ColorScheme.of(context).surface.withAlpha(10);
    final colors = [Colors.transparent, color, color, Colors.transparent];
    return _SkeletonMask(
      repaint: _controller,
      shaderCallback: (Rect bounds) {
        final width = bounds.width;
        final height = bounds.height;
        matrix[12] = width * _controller.value;
        return ui.Gradient.linear(
          Offset(0, 0.35 * height),
          Offset(width, 0.95 * height),
          colors,
          const [0.1, 0.3, 0.5, 0.7],
          TileMode.clamp,
          matrix.storage,
        );
      },
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _SkeletonMask extends ShaderMask {
  _SkeletonMask({
    required this.repaint,
    required super.shaderCallback,
    required super.child,
  }) : super(key: ObjectKey(repaint), blendMode: BlendMode.srcATop);

  final Listenable repaint;

  @override
  RenderShaderMask createRenderObject(BuildContext context) =>
      _RenderSkeletonMask(
        repaint,
        shaderCallback: shaderCallback,
        blendMode: blendMode,
      );
}

class _RenderSkeletonMask extends RenderShaderMask {
  _RenderSkeletonMask(
    this.repaint, {
    required super.shaderCallback,
    required super.blendMode,
  });

  final Listenable repaint;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    repaint.removeListener(markNeedsPaint);
    super.detach();
  }
}
