import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/cropped_image.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/utils/preview_image_cache.dart';
import 'package:pili_aurora_next/utils/cache_manager.dart';
import 'package:pili_aurora_next/utils/image_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';

Widget buildSeekPreviewWidget(
  PlPlayerController controller,
  double maxHeight,
) => Obx(() {
  final frame = controller.seekPreviewFrame.value;
  if (frame == null) return const SizedBox.shrink();

  final expanded =
      controller.isFullScreen.value &&
      (PlatformUtils.isDesktop || !controller.isVertical);
  final compatibleHeight = maxHeight - 140;
  final height = expanded ? 108.0 : 81.0;
  return Align(
    alignment: Alignment.center,
    child: ClipRRect(
      borderRadius: Style.mdRadius,
      child: VideoShotImage(
        key: ObjectKey(frame.atlas),
        url: frame.url,
        x: frame.column,
        y: frame.row,
        columns: frame.columns,
        rows: frame.rows,
        height: compatibleHeight > 50
            ? math.min(height, compatibleHeight)
            : height,
        imageCache: controller.previewCache,
      ),
    ),
  );
});

class VideoShotImage extends StatefulWidget {
  const VideoShotImage({
    super.key,
    required this.imageCache,
    required this.url,
    required this.x,
    required this.y,
    required this.columns,
    required this.rows,
    required this.height,
    this.loadImage,
  });

  final PreviewImageCache imageCache;
  final String url;
  final int x;
  final int y;
  final int columns;
  final int rows;
  final double height;
  final Future<ui.Image?> Function(String url, int height)? loadImage;

  @override
  State<VideoShotImage> createState() => _VideoShotImageState();
}

Future<ui.Image?> _getImage(
  String url,
  int height,
  bool Function() isCurrent,
) async {
  final file = await CacheManager.manager.getSingleFile(
    ImageUtils.safeThumbnailUrl(url),
    key: Utils.getFileName(url, fileExt: false),
    headers: Constants.baseHeaders,
  );
  if (!isCurrent()) return null;
  return loadImageFrame(
    File(file.path),
    owner: VideoShotImage,
    height: height,
    maxDecodePixels: 2 << 20,
    isCurrent: isCurrent,
  ).result;
}

class _VideoShotImageState extends State<VideoShotImage> {
  late double _devicePixelRatio;
  String? _requestedKey;
  int _loadGeneration = 0;
  String? _displayedUrl;
  (int, int) _displayedTile = (0, 0);
  ui.Image? _image;
  final _retiredImages = <ui.Image>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    _loadImage();
  }

  @override
  void didUpdateWidget(VideoShotImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_displayedUrl == oldWidget.url) {
      _displayedTile = (oldWidget.x, oldWidget.y);
    }
    _loadImage();
  }

  void _loadImage() {
    final url = widget.url;
    final height =
        (widget.height * _devicePixelRatio / 32).ceil() * 32 * widget.rows;
    final key = '$height:$url';
    if (_requestedKey == key) return;
    _requestedKey = key;
    final loadGeneration = ++_loadGeneration;
    final cache = widget.imageCache;
    if (cache.acquire(key) case final image?) {
      _showImage(image, url);
      return;
    }
    final generation = cache.generation;
    bool ownsCache() => cache.generation == generation;
    final load = widget.loadImage;
    cache
        .acquireOrLoad(key, () async {
          try {
            return await (load?.call(url, height) ??
                _getImage(url, height, ownsCache));
          } catch (_) {
            return null;
          }
        })
        .then((image) {
          if (image == null) return;
          if (!mounted || !ownsCache() || _loadGeneration != loadGeneration) {
            image.dispose();
            return;
          }
          setState(() => _showImage(image, url));
        });
  }

  void _showImage(ui.Image image, String url) {
    final previous = _image;
    _image = image;
    _displayedUrl = url;
    _displayedTile = (widget.x, widget.y);
    if (previous != null) {
      _retiredImages.add(previous);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_retiredImages.remove(previous)) previous.dispose();
      });
    }
  }

  final _imgPaint = Paint()..filterQuality = FilterQuality.medium;
  final _borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    final (x, y) = _displayedUrl == widget.url
        ? (widget.x, widget.y)
        : _displayedTile;
    final tileWidth = image.width / widget.columns;
    final tileHeight = image.height / widget.rows;
    final width = widget.height * tileWidth / tileHeight;
    final dst = Rect.fromLTWH(0, 0, width, widget.height);
    return CroppedImage(
      size: dst.size,
      image: image,
      srcRect: Rect.fromLTWH(
        x * tileWidth,
        y * tileHeight,
        tileWidth,
        tileHeight,
      ),
      dstRect: dst,
      rrect: RRect.fromRectAndRadius(dst, const Radius.circular(10)),
      imgPaint: _imgPaint,
      borderPaint: _borderPaint,
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    for (final image in _retiredImages) {
      image.dispose();
    }
    _retiredImages.clear();
    super.dispose();
  }
}
