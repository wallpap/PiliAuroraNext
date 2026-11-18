import 'dart:math' as math;

import 'package:flutter/rendering.dart' show SliverGridRegularTileLayout;
import 'package:flutter/widgets.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/utils/grid.dart';

/// 容量与卡片共用网格几何，底部导航留白不计入可见内容高度。
class RecommendationViewport extends StatelessWidget {
  const RecommendationViewport({
    super.key,
    required this.onChanged,
    required this.builder,
    required this.cardWidth,
  });

  final double cardWidth;
  final void Function(int items, int columns, bool active) onChanged;
  final Widget Function(
    SliverGridDelegateWithExtentAndRatio delegate,
    int items,
    SliverGridRegularTileLayout layout,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    final active = TickerMode.valuesOf(context).enabled;
    final textHeight = MediaQuery.textScalerOf(context).scale(90);
    return LayoutBuilder(
      builder: (context, constraints) {
        final delegate = SliverGridDelegateWithExtentAndRatio(
          mainAxisSpacing: Style.cardSpace,
          crossAxisSpacing: Style.cardSpace,
          maxCrossAxisExtent: cardWidth,
          childAspectRatio: Style.aspectRatio,
          mainAxisExtent: textHeight,
        );
        final layout = delegate.layoutForWidth(
          math.max(1, constraints.maxWidth),
        );
        final height = math.max(0.0, constraints.maxHeight - Style.cardSpace);
        final rows = ((height + Style.cardSpace) / layout.mainAxisStride)
            .ceil();
        final items = (rows + 1) * layout.crossAxisCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) onChanged(items, layout.crossAxisCount, active);
        });
        return builder(delegate, items, layout);
      },
    );
  }
}
