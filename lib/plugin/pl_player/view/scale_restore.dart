import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';

class PlayerScaleRestore extends StatefulWidget {
  const PlayerScaleRestore({
    super.key,
    required this.plPlayerController,
    required this.transformationController,
    required this.showRestore,
  });

  final PlPlayerController plPlayerController;
  final TransformationController transformationController;
  final RxBool showRestore;

  @override
  State<PlayerScaleRestore> createState() => _PlayerScaleRestoreState();
}

class _PlayerScaleRestoreState extends State<PlayerScaleRestore>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 255),
  );
  Animation<Matrix4>? _transform;

  void _updateTransform() {
    widget.transformationController.value = _transform!.value;
  }

  Future<void> _restore() async {
    widget.showRestore.value = false;
    _transform = _animation.drive(
      Matrix4Tween(
        begin: widget.transformationController.value,
        end: Matrix4.identity(),
      ).chain(CurveTween(curve: Curves.easeOut)),
    );
    try {
      await _animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      // 页面退出或后一次还原接管后结束本次动画。
    }
  }

  @override
  void initState() {
    super.initState();
    _animation.addListener(_updateTransform);
  }

  @override
  Widget build(BuildContext context) => Obx(
    () =>
        widget.showRestore.value && widget.plPlayerController.showControls.value
        ? Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 95),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: ColorScheme.of(context).secondaryContainer
                      .withValues(alpha: 0.8),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(15),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ),
                onPressed: _restore,
                child: const Text('还原屏幕'),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );

  @override
  void dispose() {
    _animation
      ..removeListener(_updateTransform)
      ..dispose();
    super.dispose();
  }
}
