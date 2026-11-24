import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/inactive_paint_cleanup.dart';

/// 保活标签页仅在进入视口时启用动画与图片；业务状态和滚动位置继续保留。
class TabActivity extends StatefulWidget {
  const TabActivity({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
  });

  final TabController controller;
  final int index;
  final Widget child;

  @override
  State<TabActivity> createState() => _TabActivityState();
}

class _TabActivityState extends State<TabActivity> {
  late bool _active;

  bool get _isActive {
    final controller = widget.controller;
    final index = widget.index;
    // 跨多个标签时 TabBarView 会把起点临时移到终点旁边，两端仍可见。
    return controller.indexIsChanging
        ? index == controller.index || index == controller.previousIndex
        : (controller.animation!.value - index).abs() < 1;
  }

  @override
  void initState() {
    super.initState();
    _active = _isActive;
    _listen(widget.controller);
  }

  @override
  void didUpdateWidget(TabActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unlisten(oldWidget.controller);
      _listen(widget.controller);
    }
    _active = _isActive;
  }

  void _listen(TabController controller) {
    controller.addListener(_syncActivity);
    controller.animation!.addListener(_syncActivity);
  }

  void _unlisten(TabController controller) {
    controller.removeListener(_syncActivity);
    controller.animation?.removeListener(_syncActivity);
  }

  void _syncActivity() {
    final active = _isActive;
    if (_active != active) setState(() => _active = active);
  }

  @override
  void dispose() {
    _unlisten(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: _active,
    child: InactivePaintCleanup(child: widget.child),
  );
}
