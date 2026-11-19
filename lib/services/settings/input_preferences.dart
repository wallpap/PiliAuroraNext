import 'package:pili_aurora_next/utils/storage_pref.dart';

abstract final class InputPreferences {
  static double get refreshIndicatorOffset => Pref.refreshDisplacement;
  static double get horizontalTouchSlop => Pref.touchSlopH;
  static List<double> get scrollSpring => Pref.springDescription;
}
