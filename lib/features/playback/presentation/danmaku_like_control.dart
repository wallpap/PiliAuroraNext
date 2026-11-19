import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/playback/application/video_danmaku_interactions.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

/// 用户点赞状态不在弹幕分段中，按需在操作入口查询。
class DanmakuLikeControl extends StatefulWidget {
  const DanmakuLikeControl({
    super.key,
    required this.extra,
    required this.cid,
    required this.builder,
    this.isCurrent,
    this.placeholderSize = const Size.square(36),
    this.placeholderColor,
  });

  final VideoDanmaku extra;
  final int cid;
  final bool Function()? isCurrent;
  final Widget Function(BuildContext, Future<void> Function()) builder;
  final Size placeholderSize;
  final Color? placeholderColor;

  @override
  State<DanmakuLikeControl> createState() => _DanmakuLikeControlState();
}

class _DanmakuLikeControlState extends State<DanmakuLikeControl> {
  late VideoDanmakuInteractions _interaction;
  bool _busy = false;
  bool _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(DanmakuLikeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.extra, oldWidget.extra) ||
        widget.cid != oldWidget.cid ||
        !_interaction.isCurrent) {
      _refresh();
    }
  }

  Future<bool> _refresh({bool toast = false}) async {
    final generation = ++_generation;
    final extra = widget.extra;
    final mediaIsCurrent = widget.isCurrent;
    final interaction = _interaction = VideoDanmakuInteractions(
      widget.cid,
      mediaIsCurrent: () =>
          mounted &&
          generation == _generation &&
          (mediaIsCurrent?.call() ?? true),
    );
    _loaded = false;
    _busy = true;
    try {
      final result = await interaction.refreshLike(extra);
      if (!interaction.isCurrent) return false;
      if (result is Success) {
        _loaded = true;
      } else if (toast && result is Error) {
        result.toast();
      }
      return _loaded;
    } catch (_) {
      if (interaction.isCurrent && toast) {
        const Error('未能获取弹幕点赞状态，请重试').toast();
      }
      return false;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (!_loaded || !_interaction.isCurrent) {
      setState(() => _busy = true);
      if (!await _refresh(toast: true) || !mounted) return;
    }
    final interaction = _interaction;
    setState(() => _busy = true);
    try {
      if (!interaction.isCurrent) return;
      final result = await interaction.toggleLike(widget.extra);
      if (!interaction.isCurrent) return;
      if (result case Success(response: final String message)) {
        SmartDialog.showToast(message);
      } else if (result is Error) {
        if (result is UnknownResult) _loaded = false;
        result.toast();
      }
    } finally {
      if (mounted && identical(interaction, _interaction)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _refresh(toast: true);
  }

  @override
  Widget build(BuildContext context) {
    // 分段里的默认 false 不代表当前账号未点赞，查询完成前不构建点赞按钮。
    if (!_loaded) {
      return SizedBox.fromSize(
        size: widget.placeholderSize,
        child: Center(
          child: _busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.placeholderColor,
                    semanticsLabel: '正在获取弹幕点赞状态',
                  ),
                )
              : IconButton(
                  tooltip: '重新获取弹幕点赞状态',
                  onPressed: _retry,
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: widget.placeholderColor,
                  icon: const Icon(Icons.refresh),
                ),
        ),
      );
    }
    return IgnorePointer(
      ignoring: _busy,
      child: widget.builder(context, _toggle),
    );
  }
}
