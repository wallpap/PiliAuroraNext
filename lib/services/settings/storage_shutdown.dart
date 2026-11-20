import 'package:pili_aurora_next/services/app_exit.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

final List<AppExitCleanup> storageShutdown = List.unmodifiable([
  ('compact', GStorage.compact),
  ('storage', GStorage.close),
]);
