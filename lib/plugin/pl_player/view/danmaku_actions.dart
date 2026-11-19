import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/pages/danmaku/interaction.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_control.dart';
import 'package:pili_aurora_next/pages/video/widgets/danmaku_like_control.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';

class PlayerDanmakuActions extends ChangeNotifier {
  PlayerDanmakuActions({
    required this.plPlayerController,
    required this.durationMs,
    required this.liveRoomId,
  }) {
    plPlayerController.addDanmakuRuleListener(clear);
  }

  final PlPlayerController plPlayerController;
  final int? Function() durationMs;
  final int Function() liveRoomId;

  void selectAt(Offset position) {
    final interaction = plPlayerController.danmakuInteraction;
    final item = interaction?.hitTest(position);
    if (item != null &&
        item.extra != null &&
        interaction!.select(item.identity)) {
      _suspendedDm = item;
    } else {
      interaction?.clearSelection();
      _suspendedDm = null;
      _dmOffset = null;
      notifyListeners();
    }
  }

  /// 命中弹幕的本次点击由菜单消费，失效选择也不会变成控制条点击。
  bool showAt(Offset position) {
    if (_suspendedDm == null) return false;
    if (plPlayerController.danmakuInteraction?.snapshot.any(
          (item) => item.identity == _suspendedDm!.identity && item.selected,
        ) ??
        false) {
      _dmOffset = position;
    } else {
      _suspendedDm = null;
    }
    notifyListeners();
    return true;
  }

  Widget buildOverlay(BuildContext context, double maxWidth) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) => Obx(() {
        if (!plPlayerController.enableShowDanmakuAdaptive.value) {
          return const SizedBox.shrink();
        }
        final offset = _dmOffset;
        final item = _suspendedDm;
        return offset != null && item != null
            ? _buildDmAction(context, maxWidth, item, offset)
            : const SizedBox.shrink();
      }),
    );
  }

  @override
  void dispose() {
    plPlayerController.removeDanmakuRuleListener(clear);
    _clear(notify: false);
    super.dispose();
  }

  static const _overlaySpacing = 5.0;
  static const _actionItemWidth = 40.0;
  static const _actionItemHeight = 35.0 - _triangleHeight;

  DanmakuDisplaySnapshot<DanmakuExtra>? _suspendedDm;
  Offset? _dmOffset;

  void clear() => _clear(notify: true);

  void _clear({required bool notify}) {
    if (_suspendedDm != null) {
      plPlayerController.danmakuInteraction?.clearSelection();
      _suspendedDm = null;
      _dmOffset = null;
      if (notify) notifyListeners();
    }
  }

  Widget _dmActionItem(
    Widget child, {
    required Future<void>? Function() onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final selected = _suspendedDm;
        await onTap();
        if (identical(selected, _suspendedDm)) clear();
      },
      child: SizedBox(
        width: _actionItemWidth,
        height: _actionItemHeight,
        child: Center(
          child: child,
        ),
      ),
    );
  }

  static final _timeRegExp = RegExp(r'(?:\d+[:：])?\d+[:：][0-5]?\d(?!\d)');

  int? _getValidOffset(String data) {
    if (_timeRegExp.firstMatch(data) case final timeStr?) {
      final offset = DurationUtils.parseDuration(timeStr.group(0));
      final duration = durationMs();
      if (duration != null && 0 < offset && offset * 1000 < duration) {
        return offset;
      }
    }
    return null;
  }

  Widget _buildDmAction(
    BuildContext context,
    double maxWidth,
    DanmakuDisplaySnapshot<DanmakuExtra> item,
    Offset offset,
  ) {
    final interaction = plPlayerController.danmakuInteraction;
    if (interaction == null ||
        !interaction.isValid ||
        !interaction.snapshot.any(
          (entry) => entry.identity == item.identity && entry.selected,
        )) {
      _clear(notify: false);
      return const SizedBox.shrink();
    }
    final dx = offset.dx;
    // fullscreen
    if (dx > maxWidth) {
      _clear(notify: false);
      return const SizedBox.shrink();
    }

    final seekOffset = _getValidOffset(item.text);

    final overlayWidth = _actionItemWidth * (seekOffset == null ? 3 : 4);

    final top = item.bounds.bottom + _triangleHeight + 2;

    final realLeft = dx + overlayWidth / 2;

    final left = realLeft.clamp(
      _overlaySpacing + overlayWidth,
      maxWidth - _overlaySpacing,
    );

    final right = maxWidth - left;
    final triangleOffset = realLeft - left;

    if (right > (maxWidth - item.bounds.left)) {
      _clear(notify: false);
      return const SizedBox.shrink();
    }

    final extra = item.extra;
    if (extra == null) {
      _clear(notify: false);
      return const SizedBox.shrink();
    }

    return Positioned(
      right: right,
      top: top,
      child: _DanmakuTip(
        offset: triangleOffset,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: switch (extra) {
            VideoDanmaku() => [
              DanmakuLikeControl(
                extra: extra,
                cid: plPlayerController.cid!,
                placeholderSize: const Size(
                  _actionItemWidth,
                  _actionItemHeight,
                ),
                placeholderColor: Colors.white,
                onLike: () async {
                  await HeaderControl.likeDanmaku(
                    extra,
                    plPlayerController.cid!,
                  );
                },
                builder: (context, onLike) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _dmActionItem(
                      extra.isLike
                          ? const Icon(
                              size: 20,
                              CustomIcons.player_dm_tip_like_solid,
                              color: Colors.white,
                            )
                          : const Icon(
                              size: 20,
                              CustomIcons.player_dm_tip_like,
                              color: Colors.white,
                            ),
                      onTap: onLike,
                    ),
                    if (extra.like > 0)
                      Positioned(
                        left: _actionItemWidth - 10.5,
                        top: 0,
                        child: Text(
                          extra.like.toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              _dmActionItem(
                const Icon(
                  size: 19,
                  CustomIcons.player_dm_tip_copy,
                  color: Colors.white,
                ),
                onTap: () => Utils.copyText(item.text),
              ),
              if (item.selfSend)
                _dmActionItem(
                  const Icon(
                    size: 20,
                    CustomIcons.player_dm_tip_recall,
                    color: Colors.white,
                  ),
                  onTap: () => HeaderControl.deleteDanmaku(
                    extra.id,
                    plPlayerController.cid!,
                  ),
                )
              else
                _dmActionItem(
                  const Icon(
                    size: 20,
                    CustomIcons.player_dm_tip_back,
                    color: Colors.white,
                  ),
                  onTap: () => HeaderControl.reportDanmaku(
                    context,
                    extra: extra,
                    ctr: plPlayerController,
                  ),
                ),
              if (seekOffset != null)
                _dmActionItem(
                  const Icon(
                    size: 18,
                    Icons.gps_fixed_outlined,
                    color: Colors.white,
                  ),
                  onTap: () => plPlayerController.seekTo(
                    Duration(seconds: seekOffset),
                    isSeek: false,
                  ),
                ),
            ],
            LiveDanmaku() => [
              _dmActionItem(
                const Icon(
                  size: 20,
                  MdiIcons.accountOutline,
                  color: Colors.white,
                ),
                onTap: () => Get.toNamed('/member?mid=${extra.mid}'),
              ),
              _dmActionItem(
                const Icon(
                  size: 19,
                  CustomIcons.player_dm_tip_copy,
                  color: Colors.white,
                ),
                onTap: () => Utils.copyText(item.text),
              ),
              _dmActionItem(
                const Icon(
                  size: 20,
                  CustomIcons.player_dm_tip_back,
                  color: Colors.white,
                ),
                onTap: () {
                  final room = liveRoomId();
                  return HeaderControl.reportLiveDanmaku(
                    context,
                    roomId: room,
                    msg: item.text,
                    extra: extra,
                    roomIsCurrent: () => liveRoomId() == room,
                  );
                },
              ),
            ],
          },
        ),
      ),
    );
  }
}

const double _triangleHeight = 5.6;

class _DanmakuTip extends SingleChildRenderObjectWidget {
  const _DanmakuTip({this.offset = 0, super.child});

  final double offset;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDanmakuTip(offset: offset);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDanmakuTip renderObject,
  ) {
    renderObject.offset = offset;
  }
}

class _RenderDanmakuTip extends RenderProxyBox {
  _RenderDanmakuTip({
    required this._offset,
  });

  double _offset;
  double get offset => _offset;
  set offset(double value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..color = const Color(0xB3000000)
      ..style = .fill;

    final radius = size.height / 2;
    const triangleBase = _triangleHeight * 2 / 3;

    final triangleCenterX = (size.width / 2 + _offset).clamp(
      radius + triangleBase,
      size.width - radius - triangleBase,
    );
    final path = Path()
      // triangle (exceed)
      ..moveTo(triangleCenterX - triangleBase, 0)
      ..lineTo(triangleCenterX, -_triangleHeight)
      ..lineTo(triangleCenterX + triangleBase, 0)
      // top
      ..lineTo(size.width - radius, 0)
      // right
      ..arcToPoint(
        Offset(size.width - radius, size.height),
        radius: Radius.circular(radius),
      )
      // bottom
      ..lineTo(radius, size.height)
      // left
      ..arcToPoint(
        Offset(radius, 0),
        radius: Radius.circular(radius),
      )
      ..close();

    context.canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..drawPath(path, paint)
      ..drawPath(
        path,
        paint
          ..color = const Color(0x7EFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      )
      ..restore();

    super.paint(context, offset);
  }
}
