import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/widgets/webview_ready.dart';
import 'package:pili_aurora_next/services/webview_environment.dart';

void main() {
  testWidgets('shutdown waits for Windows view creation and destruction', (
    tester,
  ) async {
    WindowsInAppWebViewPlatform.registerWith();
    AppWebViewEnvironment.configure(userDataPath: 'isolated-native-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final creating = Completer<int>();
    final destroying = Completer<void>();
    final events = <String>[];
    var delivered = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.pichillilorenzo/flutter_webview_environment'),
      (call) async {
        if (call.method == 'getAvailableVersion') return 'test';
        expectSync(call.method, 'create');
        final id = (call.arguments as Map)['id'];
        messenger.setMockMethodCallHandler(
          MethodChannel('com.pichillilorenzo/flutter_webview_environment_$id'),
          (call) async {
            expectSync(call.method, 'dispose');
            events.add('environment disposed');
            return null;
          },
        );
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager'),
      (call) async {
        if (call.method == 'createInAppWebView') {
          events.add('creating');
          return creating.future;
        }
        expectSync(call.method, 'dispose');
        expectSync(call.arguments, {'id': 42});
        events.add('destroying');
        await destroying.future;
        events.add('view disposed');
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WebViewReady(
          builder: (_) => InAppWebView(
            webViewEnvironment: AppWebViewEnvironment.instance,
            onWebViewCreated: (_) => delivered = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(events, ['creating']);
    final closing = AppWebViewEnvironment.close();
    await tester.pump();
    expect(find.byType(InAppWebView), findsNothing);
    expect(events, ['creating']);

    creating.complete(42);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(delivered, isFalse);
    expect(events, ['creating', 'destroying']);

    destroying.complete();
    await tester.pump();
    await closing;
    expect(events, [
      'creating',
      'destroying',
      'view disposed',
      'environment disposed',
    ]);
  });
}
