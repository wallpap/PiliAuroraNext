import 'package:catcher_2/catcher_2.dart';

void reportError(Object exception, [StackTrace? stack]) {
  Catcher2.reportCheckedError(exception, stack);
}
