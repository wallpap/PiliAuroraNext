import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initializeTemporaryPath() async {
  tmpDirPath = (await getTemporaryDirectory()).path;
}

Future<void> initializeSupportPath() async {
  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}
