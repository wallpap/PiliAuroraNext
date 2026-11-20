import 'package:pili_aurora_next/core/types/enum_with_label.dart';

enum DynamicBadgeMode implements EnumWithLabel {
  hidden('隐藏'),
  point('红点'),
  number('数字'),
  ;

  @override
  final String label;
  const DynamicBadgeMode(this.label);
}
