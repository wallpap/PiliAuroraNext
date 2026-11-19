import 'dart:async';
import 'dart:io' show Platform;

import 'package:dlna_dart/dlna.dart';
import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/device_utils.dart';
import 'package:pili_aurora_next/utils/permission_handler.dart';

typedef DlnaTarget = ({String key, String name});

/// 投屏路由持有 Session；设备仅在两条投屏命令均确认后成为当前设备。
final class DlnaSession extends ChangeNotifier {
  DlnaSession({
    this._manager,
    Future<PermissionStatus> Function()? requestPermission,
    this.searchDuration = const Duration(seconds: 20),
  }) : _requestPermission = requestPermission ?? _requestLocalNetwork;

  static Future<PermissionStatus> _requestLocalNetwork() async {
    if (Platform.isAndroid && DeviceUtils.sdkInt >= 37) {
      return Permission.accessLocalNetwork.request();
    }
    return PermissionStatus.granted;
  }

  DLNAManager? _manager;
  final Future<PermissionStatus> Function() _requestPermission;
  final Duration searchDuration;
  Map<String, DLNADevice> _devices = {};
  List<DlnaTarget> _targets = const [];
  final Set<DLNADevice> _ownedDevices = {};
  bool _searching = false;
  bool _connecting = false;
  String? _searchError;
  PermissionStatus? _permissionStatus;
  String? _selectedKey;
  DLNADevice? _selected;
  bool _disposed = false;
  Completer<void>? _searchDone;

  List<DlnaTarget> get targets => _targets;
  bool get searching => _searching;
  bool get connecting => _connecting;
  String? get searchError => _searchError;
  bool get permissionDenied =>
      _permissionStatus != null &&
      _permissionStatus != PermissionStatus.granted;
  bool get permissionPermanentlyDenied =>
      _permissionStatus == PermissionStatus.permanentlyDenied;
  String? get selectedKey => _selectedKey;

  Future<void> search() async {
    if (_disposed || _searching || _connecting) return;
    _searching = true;
    _searchError = null;
    _permissionStatus = null;
    _devices.clear();
    _targets = const [];
    notifyListeners();
    try {
      final permission = await _requestPermission();
      if (_disposed) return;
      _permissionStatus = permission;
      if (permission != PermissionStatus.granted) {
        _searchError = permissionPermanentlyDenied
            ? '局域网权限未授权，请在系统设置中允许附近的设备，返回后点击搜索'
            : '需要局域网权限才能搜索投屏设备';
        return;
      }
      await _discover();
    } catch (error, stackTrace) {
      logger.w('搜索投屏设备失败', error: error.runtimeType, stackTrace: stackTrace);
      if (!_disposed) {
        _searchError = '设备搜索失败，请检查局域网连接后重试';
      }
    } finally {
      _searching = false;
      _releaseWhenIdle();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _discover() async {
    final discovery = _manager ??= DLNAManager();
    DeviceManager? manager;
    StreamSubscription<Map<String, DLNADevice>>? subscription;
    Timer? timer;
    try {
      manager = await discovery.start();
      if (_disposed) return;
      final done = _searchDone = Completer<void>();
      subscription = manager.devices.stream.listen(
        (snapshot) {
          if (_disposed || done.isCompleted) return;
          _devices = Map.of(snapshot);
          _targets = List.unmodifiable([
            for (final entry in _devices.entries)
              (key: entry.key, name: entry.value.info.friendlyName),
          ]);
          _ownedDevices.addAll(_devices.values);
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) done.completeError(error, stackTrace);
        },
        onDone: _endSearch,
      );
      timer = Timer(searchDuration, _endSearch);
      await done.future;
    } finally {
      _searchDone = null;
      timer?.cancel();
      try {
        await subscription?.cancel();
      } catch (error, stackTrace) {
        logger.w(
          '释放投屏搜索订阅失败',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      }
      if (manager != null) _ownedDevices.addAll(manager.deviceList.values);
      try {
        await Future<void>.sync(discovery.stop);
      } catch (error, stackTrace) {
        logger.w('停止投屏搜索失败', error: error.runtimeType, stackTrace: stackTrace);
        if (!_disposed) _searchError = '设备搜索停止失败，请重试';
      }
    }
  }

  void _endSearch() {
    final done = _searchDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> openPermissionSettings() async {
    if (_disposed) return;
    try {
      if (await openAppSettings()) return;
    } catch (error, stackTrace) {
      logger.w('打开权限设置失败', error: error.runtimeType, stackTrace: stackTrace);
    }
    if (_disposed) return;
    _searchError = '无法打开系统设置，请手动允许局域网权限';
    notifyListeners();
  }

  Future<LoadingState<void>> connect({
    required String key,
    required String url,
    String title = '',
    required bool Function() isCurrent,
  }) async {
    if (_disposed || !isCurrent()) return const Error('投屏页面已关闭');
    if (_connecting) return const Error('正在连接设备，请稍候');
    if (key == _selectedKey) return const Success(null);
    final device = _devices[key];
    final uri = Uri.tryParse(url);
    if (device == null ||
        uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const Error('投屏地址或设备无效，请重新打开投屏');
    }
    _connecting = true;
    notifyListeners();
    bool current() => !_disposed && isCurrent();
    try {
      await device.setUrl(url, title: title);
      if (!current()) return const Error('投屏操作已取消');
      await device.play();
      if (!current()) return const Error('投屏操作已取消');
      final previous = _selected;
      _selected = device;
      _selectedKey = key;
      notifyListeners();
      if (previous != null && !identical(previous, device)) {
        try {
          await previous.pause();
        } catch (error, stackTrace) {
          logger.w(
            '新设备已连接，暂停原设备失败',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
          return Error(
            '新设备已连接，请手动暂停原设备',
            cause: error,
            stackTrace: stackTrace,
          );
        }
      }
      return const Success(null);
    } catch (error, stackTrace) {
      logger.w('连接投屏设备失败', error: error.runtimeType, stackTrace: stackTrace);
      return Error('投屏未能确认，请检查设备后重试', cause: error, stackTrace: stackTrace);
    } finally {
      _connecting = false;
      _releaseWhenIdle();
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _endSearch();
    _releaseWhenIdle();
    super.dispose();
  }

  void _releaseWhenIdle() {
    if (!_disposed || _searching || _connecting) return;
    for (final device in _ownedDevices) {
      try {
        device.dispose();
      } catch (error, stackTrace) {
        logger.w('释放投屏设备失败', error: error.runtimeType, stackTrace: stackTrace);
      }
    }
    _ownedDevices.clear();
    _devices.clear();
    _targets = const [];
    _selected = null;
  }
}
