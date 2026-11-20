import 'package:pili_aurora_next/features/playback/data/cdn_speed_probe.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/playback/domain/media/cdn_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';
import 'package:pili_aurora_next/features/playback/application/video_preferences.dart';
import 'package:material_ui/material_ui.dart';

class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget Function(BuildContext, int)? subtitleBuilder;
  final bool toggleable;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.subtitleBuilder,
    this.toggleable = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleMedium = TextTheme.of(context).titleMedium!;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(title),
      constraints: subtitleBuilder != null
          ? const BoxConstraints.tightFor(width: 320)
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Material(
        type: .transparency,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            onChanged: (v) => Navigator.of(context).pop(v ?? value),
            groupValue: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                values.length,
                (index) {
                  final item = values[index];
                  return RadioListTile<T>(
                    toggleable: toggleable,
                    dense: true,
                    value: item.$1,
                    title: Text(
                      item.$2,
                      style: titleMedium,
                    ),
                    subtitle: subtitleBuilder?.call(context, index),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CdnSelectDialog extends StatefulWidget {
  final BaseItem? sample;
  final CdnSpeedProbe Function()? createProbe;

  const CdnSelectDialog({
    super.key,
    this.sample,
    this.createProbe,
  });

  @override
  State<CdnSelectDialog> createState() => _CdnSelectDialogState();
}

class _CdnSelectDialogState extends State<CdnSelectDialog> {
  late final List<ValueNotifier<String?>> _cdnResList;
  late final CdnSpeedProbe _probe;
  late final bool _cdnSpeedTest;

  @override
  void initState() {
    super.initState();
    _cdnSpeedTest = Pref.cdnSpeedTest;
    if (_cdnSpeedTest) {
      _probe = widget.createProbe?.call() ?? CdnSpeedProbe();
      final length = CDNService.values.length;
      _cdnResList = List.generate(
        length,
        (_) => ValueNotifier<String?>(null),
      );
      _startSpeedTest();
    }
  }

  @override
  void dispose() {
    if (_cdnSpeedTest) {
      _probe.close();
      for (final notifier in _cdnResList) {
        notifier.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _startSpeedTest() async {
    try {
      final videoItem = widget.sample ?? await CdnSpeedProbe.sample();
      for (final service in CDNService.values) {
        if (!mounted) break;
        final result = await _probe.measure(service, videoItem);
        if (mounted) _cdnResList[service.index].value = result;
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      logger
          .scoped('cdnProbe')
          .w(
            'CDN 测速采样失败',
            error: e.runtimeType,
            stackTrace: stackTrace,
          );
      for (final notifier in _cdnResList) {
        notifier.value ??= '无法获取测速来源，请重试';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectDialog<CDNService>(
      title: 'CDN 设置',
      values: CDNService.values.map((i) => (i, i.desc)).toList(),
      value: VideoPreferences.cdn,
      subtitleBuilder: _cdnSpeedTest
          ? (context, index) {
              final item = _cdnResList[index];
              return ValueListenableBuilder(
                valueListenable: item,
                builder: (context, value, _) {
                  return Text(
                    value ?? '---',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              );
            }
          : null,
    );
  }
}
