import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:path_provider/path_provider.dart';

/// 记录系统临时目录，供临时文件和短期缓存使用。
Future<void> initializeTemporaryPath() async {
  tmpDirPath = (await getTemporaryDirectory()).path;
}

/// 初始化应用支持目录，作为应用配置和平台数据目录的根路径。
Future<void> initializeSupportPath() async {
  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}
