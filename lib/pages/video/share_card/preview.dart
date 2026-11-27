import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/common/media/image_actions.dart';
import 'package:pili_aurora_next/core/text/string_ext.dart';
import 'package:pili_aurora_next/pages/video/share_card/artwork.dart';
import 'package:pili_aurora_next/pages/video/share_card/content.dart';
import 'package:pili_aurora_next/platform/desktop/windows_image_clipboard.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/cache/image_cache.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showVideoShareCard(
  BuildContext context,
  VideoShareCardContent content, {
  Future<int?> Function()? loadFollowers,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭分享卡片',
  barrierColor: Colors.transparent,
  pageBuilder: (_, animation, _) => _ShareCardPreview(
    content: content,
    progress: animation.drive(CurveTween(curve: Curves.easeOut)),
    loadFollowers: loadFollowers,
  ),
  transitionBuilder: (_, _, _, child) => child,
);

class _ShareCardPreview extends StatefulWidget {
  const _ShareCardPreview({
    required this.content,
    required this.progress,
    this.loadFollowers,
  });

  final VideoShareCardContent content;
  final Animation<double> progress;
  final Future<int?> Function()? loadFollowers;

  @override
  State<_ShareCardPreview> createState() => _ShareCardPreviewState();
}

class _ShareCardPreviewState extends State<_ShareCardPreview> {
  static const _mist = Color(0xffcbc4db);
  static const _blush = Color(0xffffd1eb);

  late final _code = VideoShareCardPainter.qrImage(widget.content.url);
  ui.Image? _cover;
  ui.Image? _avatar;
  ui.Image? _artwork;
  int? _followers;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = widget.content;
    final (cover, avatar, artwork, followers) = await (
      _loadImage(content.cover, 1200),
      _loadImage(content.avatar, 96),
      _loadImage(
        content.artwork == content.cover ? null : content.artwork,
        400,
      ),
      _loadFollowers(),
    ).wait;
    if (!mounted) {
      cover?.dispose();
      avatar?.dispose();
      artwork?.dispose();
      return;
    }
    setState(() {
      _cover = cover;
      _avatar = avatar;
      _artwork = artwork;
      _followers = followers;
      _loading = false;
    });
  }

  Future<int?> _loadFollowers() async {
    try {
      return widget.content.followers ?? await widget.loadFollowers?.call();
    } catch (error, stackTrace) {
      logger.w('加载分享卡片粉丝数失败', error: error.runtimeType, stackTrace: stackTrace);
      return null;
    }
  }

  Future<ui.Image?> _loadImage(String? url, int width) async {
    if (url == null) return null;
    try {
      final file = await CacheManager.manager.getSingleFile(url.http2https);
      if (!mounted) return null;
      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: width,
        allowUpscaling: false,
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (error, stackTrace) {
      logger.w('加载分享卡片图片失败', error: error.runtimeType, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  void dispose() {
    _cover?.dispose();
    _avatar?.dispose();
    _artwork?.dispose();
    super.dispose();
  }

  VideoShareCardPainter get _painter => VideoShareCardPainter(
    content: widget.content,
    code: _code,
    cover: _cover,
    avatar: _avatar,
    artwork: _artwork,
    followers: _followers,
  );

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _export({required bool save}) async {
    if (_loading || _exporting) return;
    setState(() => _exporting = true);
    try {
      final name = widget.content.fileName;
      if (save &&
          PlatformUtils.isMobile &&
          !await ImageUtils.checkPermissionDependOnSdkInt()) {
        return;
      }
      if (!_isCurrent) return;
      final bytes = await _painter.png();
      if (!_isCurrent) return;
      if (save) {
        await ImageUtils.saveByteImg(
          bytes: bytes,
          fileName: name,
          showLoading: false,
        );
      } else if (PlatformUtils.isDesktop) {
        await WindowsImageClipboard.write(bytes);
        if (mounted) SmartDialog.showToast('已复制图片，可到目标应用粘贴');
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'image/png')],
            fileNameOverrides: ['$name.png'],
          ),
        );
      }
    } catch (error, stackTrace) {
      final message = save
          ? '图片保存失败，请重试'
          : PlatformUtils.isDesktop
          ? '图片复制失败，请重试'
          : '图片分享失败，请重试';
      logger.w(message, error: error.runtimeType, stackTrace: stackTrace);
      if (mounted) SmartDialog.showToast(message);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.isDesktop;
    void close() {
      if (_isCurrent) Navigator.of(context).pop();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: widget.progress,
                  child: const SizedBox.expand(),
                  builder: (_, child) {
                    final strength = widget.progress.value;
                    final sigma = 9 * strength;
                    return BackdropFilter(
                      filter: ui.ImageFilter.compose(
                        inner: ui.ImageFilter.blur(
                          sigmaX: sigma,
                          sigmaY: sigma,
                        ),
                        outer: ColorFilter.mode(
                          Colors.black.withValues(alpha: .65 * strength),
                          BlendMode.srcATop,
                        ),
                      ),
                      child: child,
                    );
                  },
                ),
              ),
            ),
            FadeTransition(
              opacity: widget.progress,
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Center(child: _stage(isDesktop)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(bool isDesktop) {
    final canExport = !_loading && !_exporting;
    const posterSize = VideoShareCardPainter.posterSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _loading
              ? const SizedBox(
                  height: 90,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _blush,
                      semanticsLabel: '正在生成分享卡片',
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = isDesktop ? 440.0 : 344.0;
                    final width = math.min(
                      math.min(constraints.maxWidth, maxWidth),
                      constraints.maxHeight * posterSize.aspectRatio,
                    );
                    return _card(width);
                  },
                ),
        ),
        const SizedBox(height: 12),
        Material(
          type: MaterialType.transparency,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _action(
                icon: isDesktop ? Icons.copy_outlined : Icons.ios_share,
                label: isDesktop ? '复制图片' : '分享图片',
                color: _blush,
                onPressed: canExport ? () => _export(save: false) : null,
              ),
              _action(
                icon: Icons.file_download_outlined,
                label: '保存图片',
                color: _mist,
                onPressed: canExport ? () => _export(save: true) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(double width) {
    final content = widget.content;
    const posterSize = VideoShareCardPainter.posterSize;
    return Semantics(
      container: true,
      image: true,
      label: [
        content.title,
        content.subtitle,
        ?content.author,
        content.authorMetadata(_followers),
        content.duration,
        content.watchLabel,
      ].where((value) => value.isNotEmpty).join('，'),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          boxShadow: [
            BoxShadow(
              color: Color(0x960c0b1b),
              blurRadius: 48,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: SizedBox(
            width: width,
            height: width / posterSize.aspectRatio,
            child: FittedBox(
              child: RepaintBoundary(
                child: CustomPaint(size: posterSize, painter: _painter),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: color,
      disabledForegroundColor: color.withValues(alpha: .38),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 21),
    label: Text(label),
  );
}
