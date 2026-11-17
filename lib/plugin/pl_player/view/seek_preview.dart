import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  PlPlayerController plPlayerController,
  double maxWidth,
  double maxHeight,
) {
  return Obx(
    () {
      if (!plPlayerController.showPreview.value) {
        return const SizedBox.shrink();
      }

      try {
        final data = plPlayerController.videoShot!.data;

        final double scale =
            plPlayerController.isFullScreen.value &&
                (PlatformUtils.isDesktop || !plPlayerController.isVertical)
            ? 4
            : 3;
        double height = 27 * scale;
        final compatHeight = maxHeight - 140;
        if (compatHeight > 50) {
          height = math.min(height, compatHeight);
        }

        final int imgXLen = data.imgXLen;
        final int totalPerImage = data.totalPerImage;
        double imgXSize = data.imgXSize;
        double imgYSize = data.imgYSize;

        return Align(
          alignment: Alignment.center,
          child: Obx(
            () {
              final index = plPlayerController.previewIndex.value!;
              int pageIndex = (index ~/ totalPerImage).clamp(
                0,
                data.image.length - 1,
              );
              int align = index % totalPerImage;
              int x = align % imgXLen;
              int y = align ~/ imgXLen;
              final url = data.image[pageIndex];

              return ClipRRect(
                borderRadius: Style.mdRadius,
                child: VideoShotImage(
                  url: url,
                  x: x,
                  y: y,
                  imgXSize: imgXSize,
                  imgYSize: imgYSize,
                  height: height,
                  imageCache: plPlayerController.previewCache,
                  onSetSize: (xSize, ySize) => data
                    ..imgXSize = imgXSize = xSize
                    ..imgYSize = imgYSize = ySize,
                ),
              );
            },
          ),
        );
      } catch (e) {
        if (kDebugMode) rethrow;
        return const SizedBox.shrink();
      }
    },
  );
}

class VideoShotImage extends StatefulWidget {
  const VideoShotImage({
    super.key,
    required this.imageCache,
    required this.url,
    required this.x,
    required this.y,
    required this.imgXSize,
    required this.imgYSize,
    required this.height,
    required this.onSetSize,
  });

  final PreviewImageCache imageCache;
  final String url;
  final int x;
  final int y;
  final double imgXSize;
  final double imgYSize;
  final double height;
  final Function(double imgXSize, double imgYSize) onSetSize;

  @override
  State<VideoShotImage> createState() => _VideoShotImageState();
}

Future<ui.Image?> _getImg(String url) async {
  final cacheKey = Utils.getFileName(url, fileExt: false);
  try {
    final fileInfo = await CacheManager.manager.getSingleFile(
      ImageUtils.safeThumbnailUrl(url),
      key: cacheKey,
      headers: Constants.baseHeaders,
    );
    return await _loadImg(fileInfo.path);
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _loadImg(String path) {
  return loadImageFrame(File(path), owner: VideoShotImage).result;
}

class _VideoShotImageState extends State<VideoShotImage> {
  late Size _size;
  late Rect _srcRect;
  late Rect _dstRect;
  late RRect _rrect;
  ui.Image? _image;
  int _loadGeneration = 0;
  final _retiredImages = <ui.Image>[];

  @override
  void initState() {
    super.initState();
    _initSize();
    _loadImg();
  }

  void _initSize() {
    if (widget.imgXSize == 0) {
      if (_image != null) {
        final imgXSize = _image!.width / 10;
        final imgYSize = _image!.height / 10;
        final height = widget.height;
        final width = height * imgXSize / imgYSize;
        _setRect(width, height);
        _setSrcRect(imgXSize, imgYSize);
        widget.onSetSize(imgXSize, imgYSize);
      } else {
        _setRect(double.nan, double.nan);
        _setSrcRect(widget.imgXSize, widget.imgYSize);
      }
    } else {
      final height = widget.height;
      final width = height * widget.imgXSize / widget.imgYSize;
      _setRect(width, height);
      _setSrcRect(widget.imgXSize, widget.imgYSize);
    }
  }

  void _setRect(double width, double height) {
    _size = Size(width, height);
    _dstRect = Rect.fromLTRB(0, 0, width, height);
    _rrect = RRect.fromRectAndRadius(_dstRect, const Radius.circular(10));
  }

  void _setSrcRect(double imgXSize, double imgYSize) {
    _srcRect = Rect.fromLTWH(
      widget.x * imgXSize,
      widget.y * imgYSize,
      imgXSize,
      imgYSize,
    );
  }

  void _replaceImage(ui.Image? image) {
    final previous = _image;
    _image = image;
    if (previous != null) {
      _retiredImages.add(previous);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_retiredImages.remove(previous)) {
          previous.dispose();
        }
      });
    }
  }

  void _loadImg() {
    final url = widget.url;
    final loadGeneration = ++_loadGeneration;
    _replaceImage(widget.imageCache.acquire(url));
    if (_image != null) {
      _initSize();
    } else {
      final cacheGeneration = widget.imageCache.generation;
      widget.imageCache.acquireOrLoad(url, () => _getImg(url)).then((image) {
        if (!mounted ||
            widget.imageCache.generation != cacheGeneration ||
            loadGeneration != _loadGeneration ||
            widget.url != url) {
          image?.dispose();
          return;
        }
        if (image == null) {
          return;
        }
        // 超出缓存上限的预览仍可显示，由当前组件独占，关闭时释放。
        _replaceImage(image);
        if (_image != null) {
          _initSize();
          setState(() {});
        }
      });
    }
  }

  @override
  void didUpdateWidget(VideoShotImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImg();
    } else if (oldWidget.imgXSize != widget.imgXSize ||
        oldWidget.imgYSize != widget.imgYSize ||
        oldWidget.height != widget.height) {
      _initSize();
    } else if (oldWidget.x != widget.x || oldWidget.y != widget.y) {
      _setSrcRect(_srcRect.width, _srcRect.height);
    }
  }

  late final _imgPaint = Paint()..filterQuality = FilterQuality.medium;
  late final _borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    if (_image != null) {
      return CroppedImage(
        size: _size,
        image: _image!,
        srcRect: _srcRect,
        dstRect: _dstRect,
        rrect: _rrect,
        imgPaint: _imgPaint,
        borderPaint: _borderPaint,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _image?.dispose();
    _image = null;
    for (final image in _retiredImages) {
      image.dispose();
    }
    _retiredImages.clear();
    super.dispose();
  }
}
