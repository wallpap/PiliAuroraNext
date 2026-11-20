import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class InputPreferences {
  static double get refreshIndicatorOffset => Pref.refreshDisplacement;
  static double get horizontalTouchSlop => Pref.touchSlopH;
  static List<double> get scrollSpring => Pref.springDescription;
}
