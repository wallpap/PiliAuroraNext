import 'dart:io';

import 'package:pili_aurora_next/build_config.dart';
import 'package:pili_aurora_next/services/diagnostics/redact.dart';

enum StartupPhase {
  engine('呈现引擎'),
  supportPath('应用数据目录'),
  diagnostics('诊断记录'),
  playerConnection('播放窗口连接'),
  storage('本地配置与账号'),
  resources('应用资源'),
  platformServices('平台服务'),
  requests('网络服务'),
  window('应用窗口'),
  application('应用界面');

  const StartupPhase(this.label);
  final String label;
}

sealed class StartupResult {
  const StartupResult();
}

final class StartupSuccess extends StartupResult {
  const StartupSuccess();
}

final class StartupFailure extends StartupResult implements Exception {
  const StartupFailure({
    required this.phase,
    required this.cause,
    required this.stackTrace,
  });

  final StartupPhase phase;
  final Object cause;
  final StackTrace stackTrace;

  String get message => phase == StartupPhase.storage
      ? '无法读取本地配置或账号数据。请关闭应用后重新打开；若问题持续，请保留现有数据并附上错误摘要反馈。'
      : '${phase.label}未能完成初始化。请关闭应用后重新打开；若问题持续，请附上错误摘要反馈。';

  String get diagnosticSummary => [
    'PiliAuroraNext ${BuildConfig.versionName}+${BuildConfig.versionCode}',
    'Commit: ${BuildConfig.commitHash}',
    'Platform: ${Platform.operatingSystem}',
    'Stage: ${phase.name}',
    'Cause: ${cause.runtimeType}',
    if (cause case FileSystemException(:final osError?))
      'OS error: ${osError.errorCode}',
    DiagnosticRedactor.text(stackTrace, maxLength: 8192),
  ].join('\n');

  @override
  String toString() => 'StartupFailure(${phase.name}, ${cause.runtimeType})';
}

class StartupProgress {
  StartupPhase phase = StartupPhase.engine;

  Future<StartupResult> run(Future<void> Function() initialize) async {
    try {
      await initialize();
      return const StartupSuccess();
    } catch (error, stackTrace) {
      return StartupFailure(phase: phase, cause: error, stackTrace: stackTrace);
    }
  }
}
