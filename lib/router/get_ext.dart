import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:get/get.dart';

extension GetExt on GetInterface {
  void updateMyAppTheme() {
    final (light, dark) = ThemeUtils.getAllTheme();
    rootController
      ..theme = light
      ..darkTheme = dark
      ..update();
  }

  Future<T?>? offOrToNamed<T>(
    String page, {
    dynamic arguments,
    int? id,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    bool off = false,
  }) => (off ? offNamed : toNamed)(
    page,
    arguments: arguments,
    id: id,
    preventDuplicates: preventDuplicates,
    parameters: parameters,
  );
}
