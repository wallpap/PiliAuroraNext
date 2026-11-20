import 'dart:io' show Platform;

import 'package:pili_aurora_next/platform/files/bundled_assets.dart';

/// 日常播放和解码测试共用平台输出修正。
Map<String, String> nativeVideoPlayerOptions() => {
  if (Platform.isWindows) 'gpu-dumb-mode': 'no',
  if (Platform.isWindows)
    'glsl-shaders': AssetUtils.tryGetPath(
      'assets/shaders/Windows_ChromaClamp.glsl',
    )!,
};
