import 'dart:async' show Timer;

import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/menu_row.dart';
import 'package:pili_aurora_next/services/shutdown_timer_service.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPicker;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

const _kSqueeze = 1.25;
const _kItemExtent = 38.0;

ShutdownTimerService get _service => shutdownTimerService;

Widget _pickerBuilder(
  int count, {
  required ValueChanged<int> onSelectedItemChanged,
  required FixedExtentScrollController scrollController,
}) {
  return CupertinoPicker(
    // looping: true,
    squeeze: _kSqueeze,
    itemExtent: _kItemExtent,
    scrollController: scrollController,
    onSelectedItemChanged: onSelectedItemChanged,
    children: List.generate(
      count,
      (index) => Center(
        child: Text(
          index.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 20, letterSpacing: .4),
        ),
      ),
    ),
  );
}

void _showTimePickerDialog(
  BuildContext context,
  VoidCallback onCountdown,
  StateSetter setState,
) {
  final service = _service;
  final values = service.durationInMinutes;
  var hour = values ~/ 60;
  var minute = values % 60;

  final hourController = FixedExtentScrollController(initialItem: hour);
  final minuteController = FixedExtentScrollController(initialItem: minute);

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      contentPadding: const .fromLTRB(20, 6, 20, 0),
      actionsPadding: const .fromLTRB(20, 0, 20, 16),
      constraints: const .tightFor(width: 320, height: 320),
      content: Row(
        children: [
          Expanded(
            child: _pickerBuilder(
              25,
              scrollController: hourController,
              onSelectedItemChanged: (value) => hour = value,
            ),
          ),
          const Text('时'),
          const SizedBox(width: 10),
          Expanded(
            child: _pickerBuilder(
              60,
              scrollController: minuteController,
              onSelectedItemChanged: (value) => minute = value,
            ),
          ),
          const Text('分'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(dialogContext).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            if (!context.mounted) return;
            service.startShutdownTimer(hour * 60 + minute);
            onCountdown();
            setState(() {});
          },
          child: const Text('确认'),
        ),
      ],
    ),
  ).whenComplete(() {
    hourController.dispose();
    minuteController.dispose();
  });
}

void showScheduleExitDialog(
  BuildContext context, {
  bool isLive = false,
}) {
  const Set<int> scheduleTimeMinutes = {0, 15, 30, 45, 60};
  const TextStyle titleStyle = TextStyle(fontSize: 14);
  if (isLive) {
    _service.waitUntilCompleted = false;
  }

  final child = ShutdownPanel(
    builder: (context, countdown, onCountdown, setState) {
      final theme = Theme.of(context);
      final isPortrait =
          MediaQuery.orientationOf(context) == Orientation.portrait;
      return Padding(
        padding: const .fromLTRB(12, 12, 12, 0),
        child: Material(
          clipBehavior: .hardEdge,
          color: theme.colorScheme.surface,
          borderRadius: isPortrait
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(12),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const .symmetric(vertical: 14),
              children: [
                Stack(
                  alignment: .center,
                  clipBehavior: .none,
                  children: [
                    const Text('定时关闭', style: titleStyle),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 16,
                      child: countdown,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...{...scheduleTimeMinutes, _service.durationInMinutes}
                    .sorted(Comparable.compare)
                    .map(
                      (minutes) => ListTile(
                        dense: true,
                        onTap: () {
                          Navigator.pop(context);
                          _service.startShutdownTimer(minutes);
                        },
                        title: Text(
                          switch (minutes) {
                            0 => '禁用',
                            _ => formatShutdownMinutes(minutes),
                          },
                          style: titleStyle,
                        ),
                        trailing: _service.durationInMinutes == minutes
                            ? Icon(
                                size: 20,
                                Icons.done,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                ListTile(
                  dense: true,
                  onTap: () =>
                      _showTimePickerDialog(context, onCountdown, setState),
                  title: const Text('自定义', style: titleStyle),
                ),
                if (!isLive) ...[
                  Builder(
                    builder: (context) {
                      void onChanged([_]) {
                        _service.waitUntilCompleted =
                            !_service.waitUntilCompleted;
                        (context as Element).markNeedsBuild();
                      }

                      return ListTile(
                        dense: true,
                        onTap: onChanged,
                        title: const Text('额外等待视频播放完毕', style: titleStyle),
                        trailing: Transform.scale(
                          alignment: .centerRight,
                          scale: 0.8,
                          child: Switch(
                            value: _service.waitUntilCompleted,
                            onChanged: onChanged,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 5),
                Padding(
                  padding: const .only(left: 18),
                  child: Builder(
                    builder: (context) {
                      return Row(
                        spacing: 12,
                        children: [
                          const Text('倒计时结束:', style: titleStyle),
                          ...ShutdownAction.values.map(
                            (e) => ActionRowLineItem(
                              onTap: () {
                                _service.action = e;
                                (context as Element).markNeedsBuild();
                              },
                              text: e == .pause ? ' 暂停视频 ' : ' 退出APP ',
                              selectStatus: _service.action == e,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  PageUtils.showVideoBottomSheet(
    context,
    maxWidth: 512,
    child: isLive ? Theme(data: ThemeUtils.darkTheme, child: child) : child,
  );
}

typedef ShutdownStatefulWidgetBuilder = Widget Function(
  BuildContext context,
  Widget countdown,
  VoidCallback onCountdown,
  StateSetter setState,
);

class ShutdownPanel extends StatefulWidget {
  const ShutdownPanel({
    super.key,
    required this.builder,
    this.buildCountdownText = _kBuildCountdownText,
  });

  final ShutdownStatefulWidgetBuilder builder;
  final Widget Function(String? text) buildCountdownText;

  static Widget _kBuildCountdownText(String? text) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Text(text);
  }

  @override
  State<ShutdownPanel> createState() => _ShutdownPanelState();
}

class _ShutdownPanelState extends State<ShutdownPanel> with ShutdownMixin {
  @override
  Widget build(BuildContext context) {
    final countdown = ValueListenableBuilder<String?>(
      valueListenable: _countdownText,
      builder: (_, text, _) => widget.buildCountdownText(text),
    );
    return widget.builder(context, countdown, _startTimer, setState);
  }
}

mixin ShutdownMixin<T extends StatefulWidget> on State<T> {
  Timer? _countdownTimer;
  final _countdownText = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _updateCountdownTextEnd([String? value]) {
    _stopTimer();
    _countdownText.value = value;
  }

  bool _updateCountdownText([_]) {
    if (shutdownTimerService.isWaiting) {
      _updateCountdownTextEnd('当前播放结束后关闭');
      return false;
    }
    final deadline = shutdownTimerService.deadline;
    if (deadline == null) {
      _updateCountdownTextEnd();
      return false;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= .zero) {
      _updateCountdownTextEnd();
      return false;
    }
    _countdownText.value = DurationUtils.formatDuration(remaining.inSeconds);
    return true;
  }

  void _startTimer() {
    _stopTimer();
    if (_updateCountdownText()) {
      _countdownTimer = .periodic(
        const Duration(seconds: 1),
        _updateCountdownText,
      );
    }
  }

  void _stopTimer() {
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _countdownText.dispose();
    super.dispose();
  }
}
