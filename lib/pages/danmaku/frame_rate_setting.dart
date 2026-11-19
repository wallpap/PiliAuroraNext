import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/danmaku/application/danmaku_preferences.dart';

/// 帧率变更需要通知正在播放的弹幕屏幕，保留其控制器和现有弹幕。
class DanmakuFrameRateSetting extends ConsumerWidget {
  const DanmakuFrameRateSetting({super.key, required this.builder});

  final Widget Function(BuildContext context, int frameRate) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      builder(context, ref.watch(danmakuFrameRateProvider));
}
