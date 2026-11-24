import 'package:pili_aurora_next/services/diagnostics/redact.dart';

enum DiagnosticLogLevel {
  trace('跟踪', '最详细的事件与耗时'),
  debug('调试', '请求、缓存与播放过程'),
  info('信息', '主要状态变化'),
  warning('警告', '异常情况与错误（默认）'),
  error('错误', '仅记录失败'),
  off('关闭', '停止此通道的日志保存');

  const DiagnosticLogLevel(this.label, this.description);
  final String label;
  final String description;

  static DiagnosticLogLevel parse(String? value) =>
      values.where((level) => level.name == value).firstOrNull ?? warning;
}

enum DiagnosticLogChannel { runtime, player }

final class DiagnosticLogRecord {
  DiagnosticLogRecord({
    required this.channel,
    required this.level,
    required this.category,
    required Object? message,
    this.time,
    this.runId,
    this.processId,
    this.windowId,
    this.sequence,
    this.elapsedUs,
    this.route,
    this.session,
    Object? details,
    Object? stack,
  }) : message = message is Map || message is Iterable
           ? DiagnosticRedactor.snapshot(message, immutable: true)
           : DiagnosticRedactor.boundedText(
               message,
               maxLength: channel == DiagnosticLogChannel.player
                   ? 65536
                   : 16384,
             ),
       details = details == null
           ? null
           : DiagnosticRedactor.snapshot(
               details,
               maxCharacters: channel == DiagnosticLogChannel.player
                   ? 262144
                   : 8192,
               maxStringLength: channel == DiagnosticLogChannel.player
                   ? 65536
                   : 4096,
               immutable: true,
             ),
       stack = stack == null
           ? null
           : DiagnosticRedactor.boundedText(
               stack,
               maxLength: channel == DiagnosticLogChannel.player ? 65536 : 4096,
             );

  factory DiagnosticLogRecord.fromJson(
    Map<String, Object?> json, {
    DiagnosticLogChannel? channel,
    int? windowId,
  }) => DiagnosticLogRecord(
    channel:
        channel ??
        (json['channel'] == 'player'
            ? DiagnosticLogChannel.player
            : DiagnosticLogChannel.runtime),
    level: DiagnosticLogLevel.parse(_value<String>(json, 'level')),
    category: _value<String>(json, 'category') ?? 'app',
    message: json['message'],
    time: DateTime.tryParse(_value<String>(json, 'time') ?? '')?.toUtc(),
    runId: _value<String>(json, 'runId'),
    processId: _value<int>(json, 'processId'),
    windowId: windowId ?? _value<int>(json, 'windowId'),
    sequence: _value<int>(json, 'sequence'),
    elapsedUs: _value<int>(json, 'elapsedUs'),
    route: _value<String>(json, 'route'),
    session: _value<String>(json, 'session'),
    details: json['details'],
    stack: _value<String>(json, 'stack'),
  );

  static const schemaVersion = 1;

  static Value? _value<Value>(Map<String, Object?> json, String key) {
    final value = json[key];
    return value is Value ? value : null;
  }

  final DiagnosticLogChannel channel;
  final DiagnosticLogLevel level;
  final String category;
  final Object? message;
  final DateTime? time;
  final String? runId;
  final int? processId;
  final int? windowId;
  final int? sequence;
  final int? elapsedUs;
  final String? route;
  final String? session;
  final Object? details;
  final String? stack;

  late final String? _wireTime = time?.toIso8601String();

  static int compare(DiagnosticLogRecord left, DiagnosticLogRecord right) {
    final leftTime = left.time;
    final rightTime = right.time;
    if (leftTime == null && rightTime != null) return -1;
    if (rightTime == null && leftTime != null) return 1;
    if (leftTime != null && rightTime != null) {
      final order = leftTime.compareTo(rightTime);
      if (order != 0) return order;
    }
    final run = (left.runId ?? '').compareTo(right.runId ?? '');
    if (run != 0) return run;
    return (left.sequence ?? 0).compareTo(right.sequence ?? 0);
  }

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'time': ?_wireTime,
    'runId': ?runId,
    'processId': ?processId,
    'windowId': ?windowId,
    'route': ?route,
    'sequence': ?sequence,
    'elapsedUs': ?elapsedUs,
    'channel': channel.name,
    'level': level.name,
    'category': category,
    'message': message,
    'details': ?details,
    'stack': ?stack,
    'session': ?session,
  };
}
