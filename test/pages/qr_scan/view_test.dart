import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/pages/qr_scan/view.dart';

class _Scanner extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture>.broadcast();
  bool permissionDenied = false;
  bool running = false;
  final analyzedImages = <String>[];

  @override
  Stream<BarcodeCapture> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    expect(startOptions.formats, [BarcodeFormat.qrCode]);
    if (permissionDenied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    running = true;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> stop() async => running = false;

  @override
  Future<void> dispose() async => running = false;

  @override
  Future<BarcodeCapture> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async {
    expect(formats, [BarcodeFormat.qrCode]);
    analyzedImages.add(path);
    return _videoCapture;
  }
}

const _videoCapture = BarcodeCapture(
  barcodes: [
    Barcode(rawValue: 'https://example.org/qr'),
    Barcode(rawValue: 'bilibili://video/42?cid=99'),
  ],
);

void main() {
  final original = MobileScannerPlatform.instance;
  late _Scanner scanner;
  setUp(() {
    scanner = _Scanner();
    MobileScannerPlatform.instance = scanner;
  });
  tearDown(() async {
    await scanner.captures.close();
    MobileScannerPlatform.instance = original;
    Get.reset();
  });

  Future<void> openScanner(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        navigatorObservers: [routeObserver, FlutterSmartDialog.observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => QrScanPage.open(context),
              child: const Text('打开扫码'),
            ),
          ),
        ),
        getPages: [
          GetPage(
            name: '/videoV',
            page: () => Scaffold(body: Text('视频 ${Get.arguments['cid']}')),
          ),
        ],
      ),
    );
    await tester.tap(find.text('打开扫码'));
    await tester.pumpAndSettle();
    expect(find.text('扫一扫'), findsOneWidget);
  }

  testWidgets('相机前后台切换后，仅接受一次有效扫码并退出取景页', (tester) async {
    await openScanner(tester);
    expect(scanner.running, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(scanner.running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scanner.running, isTrue);

    scanner.captures
      ..add(_videoCapture)
      ..add(_videoCapture);
    await tester.pumpAndSettle();
    expect(find.text('视频 99'), findsOneWidget);
    expect(scanner.running, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('打开扫码'), findsOneWidget);
    expect(find.text('扫一扫'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('相机无权限时仍可从相册识别分享图片', (tester) async {
    scanner.permissionDenied = true;
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(picker, (call) async {
        expect(call.method, 'pickImage');
        return 'share-card.jpg';
      });
    addTearDown(() => messenger.setMockMethodCallHandler(picker, null));

    await openScanner(tester);
    expect(find.text('相机权限未开启，可在系统设置中授权'), findsOneWidget);
    await tester.tap(find.byTooltip('从相册识别'));
    await tester.pumpAndSettle();
    expect(scanner.analyzedImages, ['share-card.jpg']);
    expect(find.text('视频 99'), findsOneWidget);
    expect(scanner.running, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
