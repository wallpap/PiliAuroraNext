import 'dart:async' show unawaited;
import 'dart:math' show min;

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/router/app_scheme.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:synchronized/synchronized.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  static Future<void> open(BuildContext context) async {
    final source = ModalRoute.of(context);
    final uri = await Navigator.of(context).push(
      MaterialPageRoute<Uri>(builder: (_) => const QrScanPage()),
    );
    if (uri == null || !context.mounted || source?.isCurrent == false) return;
    if (!await PiliScheme.routePush(uri, selfHandle: true) &&
        context.mounted &&
        source?.isCurrent != false) {
      SmartDialog.showToast('暂时无法打开此哔哩哔哩链接');
    }
  }

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with WidgetsBindingObserver {
  static const _formats = [BarcodeFormat.qrCode];
  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: _formats,
  );
  final _cameraLock = Lock();
  ModalRoute<dynamic>? _route;
  bool _pickingImage = false;
  bool _finished = false;

  bool get _isCurrent => mounted && !_finished && _route?.isCurrent == true;
  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    routeObserver.addNavigationListener(_onNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_updateCamera());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _onNavigation() => unawaited(_updateCamera());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_updateCamera());
  }

  Future<void> _updateCamera({bool retry = false}) =>
      _cameraLock.synchronized(() async {
        if (!mounted) return;
        try {
          if (_isCurrent && !_pickingImage && _isForeground) {
            if (retry || _controller.value.error == null) {
              await _controller.start();
            }
          } else {
            await _controller.stop();
          }
        } catch (error, stackTrace) {
          logger.w(
            '切换扫码相机状态失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        }
      });

  void _onDetect(BarcodeCapture capture) {
    if (!_pickingImage && _isForeground) _handleCapture(capture);
  }

  void _handleCapture(BarcodeCapture? capture) {
    if (!_isCurrent) return;
    final codes = capture?.barcodes;
    if (codes == null || codes.isEmpty) {
      SmartDialog.showToast('图片中未找到二维码');
      return;
    }
    for (final code in codes) {
      final uri = PiliScheme.parseScannedLink(code.rawValue);
      if (uri != null) {
        _finished = true;
        unawaited(_updateCamera());
        Navigator.of(context).pop(uri);
        return;
      }
    }
    SmartDialog.showToast('未识别到哔哩哔哩链接');
  }

  Future<void> _pickImage() async {
    if (!_isCurrent || _pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      await _updateCamera();
      if (!_isCurrent) return;
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!_isCurrent || image == null) return;
      final capture = await _controller.analyzeImage(
        image.path,
        formats: _formats,
      );
      _handleCapture(capture);
    } catch (error, stackTrace) {
      logger.w('识别相册二维码失败', error: error.runtimeType, stackTrace: stackTrace);
      if (_isCurrent) SmartDialog.showToast('无法读取或识别这张图片');
    } finally {
      if (_isCurrent) {
        setState(() => _pickingImage = false);
        unawaited(_updateCamera());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.removeNavigationListener(_onNavigation);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫一扫'),
        actions: [
          IconButton(
            tooltip: '从相册识别',
            onPressed: _pickingImage ? null : _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final side = min(280.0, size.shortestSide * 0.72);
          final frame = Rect.fromCenter(
            center: size.center(Offset.zero),
            width: side,
            height: side,
          );
          return MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: frame,
            overlayBuilder: (context, _) => Center(
              child: SizedBox.square(
                dimension: side,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const .all(.circular(16)),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const .all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? '相机权限未开启，可在系统设置中授权'
                          : '无法启动相机',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _pickingImage
                          ? null
                          : () => _updateCamera(retry: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
