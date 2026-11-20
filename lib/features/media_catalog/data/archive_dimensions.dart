import 'package:pili_aurora_next/generated/bilibili/app/archive/v1.pb.dart'
    show Dimension;

extension DimensionExt on Dimension {
  bool get isVertical => rotate == .ONE ? width > height : height > width;
}
