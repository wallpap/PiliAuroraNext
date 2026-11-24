import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_select_field.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/diagnostics/redact.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showDiagnosticLogLevelDialog(
  BuildContext context, {
  Diagnostics? diagnostics,
  bool player = false,
}) async {
  final service = diagnostics ?? Diagnostics.instance;
  final selected = await showDialog<DiagnosticLogLevel>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(player ? '播放日志等级' : '日志等级'),
      children: [
        for (final level in DiagnosticLogLevel.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(level),
            child: ListTile(
              title: Text(level.label),
              subtitle: Text(level.description),
              trailing: level == (player ? service.playerLevel : service.level)
                  ? const Icon(Icons.check)
                  : null,
            ),
          ),
      ],
    ),
  );
  if (selected != null) {
    try {
      await service.configure(
        level: player ? null : selected,
        playerLevel: player ? selected : null,
      );
    } catch (_) {
      if (context.mounted) _message(context, '日志等级已调整，但设置保存失败');
    }
  }
}

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, this.diagnostics, this.showAppBar = true});
  final bool showAppBar;
  final Diagnostics? diagnostics;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late final service = widget.diagnostics ?? Diagnostics.instance;
  bool _exporting = false;
  bool _showPerformance = false;
  DiagnosticLogChannel? _channel;
  DiagnosticLogLevel? _minimumLevel;
  final _queryController = TextEditingController();
  String _query = '';
  List<DiagnosticLogRecord>? _filteredSource;
  List<DiagnosticLogRecord> _filteredLogs = const [];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _changeFilters(VoidCallback change) => setState(() {
    change();
    _filteredSource = null;
  });

  List<DiagnosticLogRecord> _filter(List<DiagnosticLogRecord> events) {
    if (identical(_filteredSource, events)) return _filteredLogs;
    _filteredSource = events;
    if (_channel == null && _minimumLevel == null && _query.isEmpty) {
      return _filteredLogs = events;
    }
    return _filteredLogs = [
      for (final event in events)
        if ((_channel == null || event.channel == _channel) &&
            (_minimumLevel == null ||
                event.level.index >= _minimumLevel!.index) &&
            (_query.isEmpty ||
                event.category.toLowerCase().contains(_query) ||
                (event.route?.toLowerCase().contains(_query) ?? false) ||
                '${event.message}'.toLowerCase().contains(_query)))
          event,
    ];
  }

  Future<void> _configure({bool? tracing, int? intervalMs}) async {
    try {
      await service.configure(tracing: tracing, intervalMs: intervalMs);
    } catch (_) {
      if (mounted) _message(context, '设置保存失败');
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    DiagnosticExportResult? exported;
    var failed = false;
    try {
      exported = await service.exportArchive();
      final warnings = [
        if (exported.skippedChildWindows.isNotEmpty)
          '未包含 ${exported.skippedChildWindows.length} 个未连接窗口',
        if (exported.skippedRecords > 0)
          '略过 ${exported.skippedRecords} 条损坏或未写完的记录',
      ].join('，');
      if (!mounted) return;
      if (PlatformUtils.isDesktop) {
        final destination = await FilePicker.saveFile(
          bytes: Uint8List(0),
          fileName:
              'PiliAuroraNext-diagnostics-${DateTime.now().millisecondsSinceEpoch}.zip',
        );
        if (destination != null) {
          await exported.file.copy(destination.toFilePath());
          if (mounted) {
            _message(
              context,
              warnings.isEmpty ? '诊断包已导出' : '诊断包已导出，$warnings',
            );
          }
        }
      } else {
        final shared = await SharePlus.instance.share(
          ShareParams(files: [XFile(exported.file.path)]),
        );
        if (mounted &&
            shared.status != ShareResultStatus.dismissed &&
            warnings.isNotEmpty) {
          _message(context, '诊断包$warnings');
        }
      }
    } on DiagnosticExportException catch (error) {
      failed = true;
      if (mounted) {
        _message(context, switch (error.stage) {
          DiagnosticExportStage.prepare => '无法创建临时诊断目录，请检查存储空间和权限',
          DiagnosticExportStage.snapshot => '收集诊断记录失败，请检查子窗口连接和存储空间',
          DiagnosticExportStage.archive => '诊断包脱敏或压缩失败，请重试',
        });
      }
    } catch (_) {
      failed = true;
      if (mounted) {
        _message(
          context,
          PlatformUtils.isDesktop ? '保存诊断包失败，请检查目标目录和存储空间' : '分享诊断包失败，请重试',
        );
      }
    } finally {
      // 只清理本次导出创建的临时目录。
      try {
        await exported?.dispose();
      } catch (_) {
        if (mounted && !failed) _message(context, '临时诊断包清理失败');
      }
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除诊断记录'),
        content: const Text('停止性能记录，并清除本机保存的异常、运行、播放和性能记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await service.clear();
        if (mounted && service.skippedChildWindows.isNotEmpty) {
          _message(
            context,
            '已清除可协调的日志，保留 ${service.skippedChildWindows.length} 个未连接窗口的本地记录',
          );
        }
      } catch (_) {
        if (mounted) _message(context, '清除失败');
      }
    }
  }

  String _number(Object? value, String suffix, {double divisor = 1}) =>
      value is num ? '${(value / divisor).toStringAsFixed(1)}$suffix' : '不可用';
  Widget _metrics(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final child in children)
          SizedBox(width: (constraints.maxWidth - 8) / 2, child: child),
      ],
    ),
  );

  Widget _metric(String title, String value) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final latest = service.latest;
      final process = latest?['process'] as Map? ?? const {};
      final frames = latest?['frames'] as Map? ?? const {};
      final images = latest?['images'] as Map? ?? const {};
      final events = service.recentEvents;
      final logs = _filter(events);
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text('日志与诊断'),
                actions: [
                  IconButton(
                    tooltip: '导出诊断包',
                    onPressed: _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                  ),
                  IconButton(
                    tooltip: '清除诊断记录',
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              )
            : null,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.showAppBar)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _exporting ? null : _export,
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text('导出诊断包'),
                          ),
                          TextButton.icon(
                            onPressed: _clear,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('清除记录'),
                          ),
                        ],
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('日志等级'),
                      subtitle: Text(service.level.description),
                      trailing: Text(service.level.label),
                      onTap: () => showDiagnosticLogLevelDialog(
                        context,
                        diagnostics: service,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('播放日志等级'),
                      subtitle: Text(
                        '${service.playerLevel.description}；用于定位播放与解码问题',
                      ),
                      trailing: Text(service.playerLevel.label),
                      onTap: () => showDiagnosticLogLevelDialog(
                        context,
                        diagnostics: service,
                        player: true,
                      ),
                    ),
                    const Text('记录保存在本机并自动轮转。详细日志会增加存储与采样开销。'),
                    const SizedBox(height: 16),
                    if (service.storageError != null ||
                        service.droppedRecords > 0)
                      Text(
                        '写入异常：${service.storageError ?? '无'}；丢弃记录：${service.droppedRecords}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('性能记录'),
                      subtitle: Text(
                        service.tracing ? '正在记录' : '按需记录 CPU、内存与帧耗时',
                      ),
                      trailing: Icon(
                        _showPerformance
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () =>
                          setState(() => _showPerformance = !_showPerformance),
                    ),
                    if (_showPerformance) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('记录性能'),
                        subtitle: Text(
                          service.tracing
                              ? '正在记录性能和内存，自动对照播放、全屏与退出阶段；复现后导出诊断包'
                              : '关闭时不进行性能和内存定时采样',
                        ),
                        value: service.tracing,
                        onChanged: (value) => _configure(tracing: value),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('采样间隔'),
                        trailing: AppSelectField<int>(
                          value: service.intervalMs,
                          label: '采样间隔',
                          selectedLabel: switch (service.intervalMs) {
                            250 => '250 毫秒',
                            1000 => '1 秒（推荐）',
                            5000 => '5 秒',
                            final value => '$value 毫秒',
                          },
                          options: const [
                            (250, '250 毫秒'),
                            (1000, '1 秒（推荐）'),
                            (5000, '5 秒'),
                          ],
                          onSelected: (value) => _configure(intervalMs: value),
                          width: 140,
                          menuWidth: 200,
                        ),
                      ),
                      if (latest == null)
                        const Text('开启后显示采样结果')
                      else ...[
                        Text(
                          '${service.tracing ? '最新采样' : '已停止 · 最后采样'}  #${latest['sequence']}  ${latest['route']}',
                        ),
                        const SizedBox(height: 8),
                        _metrics([
                          _metric(
                            '进程工作集',
                            _number(
                              process['rssBytes'],
                              ' MiB',
                              divisor: 1048576,
                            ),
                          ),
                          _metric(
                            '启动以来峰值',
                            _number(
                              process['peakRssBytes'],
                              ' MiB',
                              divisor: 1048576,
                            ),
                          ),
                          _metric(
                            '私有提交',
                            _number(
                              process['privateBytes'],
                              ' MiB',
                              divisor: 1048576,
                            ),
                          ),
                          _metric(
                            '进程 CPU / 全机',
                            _number(process['cpuPercentMachine'], '%'),
                          ),
                          _metric(
                            '图片 LRU',
                            _number(
                              images['cacheBytes'],
                              ' MiB',
                              divisor: 1048576,
                            ),
                          ),
                          _metric(
                            '本周期慢帧',
                            '${frames['slowFrames'] ?? 0} / ${frames['count'] ?? 0}',
                          ),
                          _metric(
                            'UI 构建峰值',
                            _number(frames['maxBuildMs'], ' ms'),
                          ),
                          _metric(
                            '光栅化峰值',
                            _number(frames['maxRasterMs'], ' ms'),
                          ),
                        ]),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '缓存值属于进程内存的一部分，不可相加。GPU、Dart 堆及各模块独占内存不可直接测量；“不可用”不表示为零。',
                          ),
                        ),
                        ExpansionTile(
                          title: const Text('各部分详细指标'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              // 折叠时子树不在树上；用 Builder 把美化 JSON 推迟到展开时再做，
                              // 否则每 250ms 一次的重绘都会序列化整份采样。
                              child: Builder(
                                builder: (_) =>
                                    SelectableText(service.snapshotText()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const Divider(height: 32),
                    Text(
                      '最近日志 · ${logs.length} / ${events.length} 条',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _queryController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: '搜索消息、类别或路由',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _queryController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空搜索',
                                onPressed: () => _changeFilters(() {
                                  _queryController.clear();
                                  _query = '';
                                }),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (value) => _changeFilters(
                        () => _query = value.trim().toLowerCase(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (channel, label) in const [
                          (null, '全部'),
                          (DiagnosticLogChannel.runtime, '应用'),
                          (DiagnosticLogChannel.player, '播放'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _channel == channel,
                            onSelected: (_) =>
                                _changeFilters(() => _channel = channel),
                          ),
                        for (final (level, label) in const [
                          (DiagnosticLogLevel.warning, '警告及以上'),
                          (DiagnosticLogLevel.error, '错误'),
                        ])
                          FilterChip(
                            label: Text(label),
                            selected: _minimumLevel == level,
                            onSelected: (selected) => _changeFilters(
                              () => _minimumLevel = selected ? level : null,
                            ),
                          ),
                      ],
                    ),
                    if (logs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          events.isEmpty
                              ? '暂无日志。可调高日志详细程度后复现问题。'
                              : '没有符合当前筛选条件的日志。',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: logs.length,
              findChildIndexCallback: (key) {
                if (key is! ObjectKey) return null;
                final index = logs.indexOf(key.value as DiagnosticLogRecord);
                return index < 0 ? null : index;
              },
              itemBuilder: (context, index) {
                final log = logs[index];
                return _LogCard(key: ObjectKey(log), record: log);
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      );
    },
  );
}

class _LogCard extends StatefulWidget {
  const _LogCard({super.key, required this.record});
  final DiagnosticLogRecord record;

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _expanded = false;
  late final _record = widget.record;
  late final _time = _record.time?.toLocal();
  late final _messageText = '${_record.message}';
  late final _detailsText = switch (_record.details) {
    final String text => text,
    final Object value => const JsonEncoder.withIndent('  ').convert(value),
    null => null,
  };

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent(
            '  ',
          ).convert(DiagnosticRedactor.exportRecord(_record.toJson())),
        ),
      );
      if (mounted) _message(context, '日志已复制');
    } catch (_) {
      if (mounted) _message(context, '复制日志失败，请重试');
    }
  }

  Widget _detail(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(text),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final level = _record.level;
    final time = _time;
    final metadataStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _messageText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            level.label,
                            style: metadataStyle?.copyWith(
                              color: switch (level) {
                                DiagnosticLogLevel.error => colors.error,
                                DiagnosticLogLevel.warning => colors.tertiary,
                                _ => colors.onSurfaceVariant,
                              },
                            ),
                          ),
                          Text(_record.category, style: metadataStyle),
                          if (time != null)
                            Text(
                              '${localizations.formatShortDate(time)} '
                              '${time.toIso8601String().substring(11, 19)}',
                              style: metadataStyle,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '复制日志',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: _copy,
                ),
                IconButton(
                  tooltip: _expanded ? '收起' : '展开',
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              _detail('消息', _messageText),
              _detail(
                '来源',
                [
                  _record.channel == DiagnosticLogChannel.player ? '播放' : '应用',
                  if (_record.windowId case final value?) '窗口 $value',
                  if (_record.processId case final value?) '进程 $value',
                  ?_record.route,
                  if (_record.sequence case final value?) '#$value',
                ].join(' · '),
              ),
              if (_detailsText case final value?) _detail('详情', value),
              if (_record.stack case final value?) _detail('堆栈', value),
            ],
          ],
        ),
      ),
    );
  }
}
