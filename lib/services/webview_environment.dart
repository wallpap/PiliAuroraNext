import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 启动时只登记目录；第一次网页或 Cookie 操作共享同一份初始化。
abstract final class AppWebViewEnvironment {
  static WebViewEnvironment? _instance;
  static WebViewEnvironment? get instance => _instance;
  static String? _userDataPath;
  static Future<void>? _initializing;
  static Future<void>? _disposing;
  static Future<void>? _closing;
  static Completer<void>? _leasesReleased;
  static Timer? _idle;
  static int _users = 0;
  static bool get isConfigured => _userDataPath != null;

  /// 页面和 Cookie 操作各持有租约，避免关闭一个页面时销毁其他使用者的环境。
  static void Function() retain() {
    if (_closing != null) throw StateError('网页环境已关闭');
    if (!isConfigured) return () {};
    _idle?.cancel();
    _idle = null;
    _users++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_users == 0) {
        if (_leasesReleased case final released?) {
          released.complete();
          return;
        }
        // 给原生 Widget 的异步销毁和连续打开页面留出交接时间。
        late final Timer idle;
        _idle = idle = Timer(const Duration(seconds: 5), () {
          unawaited(_disposeIdle(idle));
        });
      }
    };
  }

  static Future<T> using<T>(Future<T> Function() action) async {
    final release = retain();
    try {
      await ensureInitialized();
      return await action();
    } finally {
      release();
    }
  }

  static Future<void> _disposeIdle(Timer idle) async {
    try {
      await _initializing;
      if (!identical(_idle, idle) || _users != 0) return;
      _idle = null;
      await _disposeEnvironment();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'WebView environment idle disposal',
        ),
      );
    }
  }

  static Future<void> _disposeEnvironment() async {
    if (_disposing case final pending?) return pending;
    final environment = _instance;
    if (environment == null) return;
    _instance = null;
    final disposal = _disposing = Future<void>.sync(environment.dispose);
    try {
      await disposal;
    } finally {
      _disposing = null;
    }
  }

  static Future<void> close() {
    if (!isConfigured) return Future.value();
    return _closing ??= _close();
  }

  static Future<void> _close() async {
    _idle?.cancel();
    _idle = null;
    if (_users > 0) await (_leasesReleased = Completer<void>()).future;
    try {
      await _initializing;
    } finally {
      await _disposeEnvironment();
    }
  }

  static void configure({required String userDataPath}) {
    if (_userDataPath != null && _userDataPath != userDataPath) {
      throw StateError('WebView directory already configured');
    }
    _userDataPath = userDataPath;
  }

  static Future<void> initialize({required String userDataPath}) async {
    configure(userDataPath: userDataPath);
    await ensureInitialized();
  }

  static Future<void> ensureInitialized() {
    // 非 Windows 不登记目录，继续使用平台自己的默认环境。
    if (_userDataPath == null || _instance != null) return Future.value();
    if (_closing != null && _users == 0) {
      return Future.error(StateError('网页环境已关闭'));
    }
    return _initializing ??= _create();
  }

  static Future<void> _create() async {
    try {
      await _disposing;
      if (await WebViewEnvironment.getAvailableVersion() != null) {
        _instance = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: _userDataPath!),
        );
      }
    } finally {
      // 失败后允许显式重试，不让失败的 Future 固化整个应用生命周期。
      _initializing = null;
    }
  }
}
