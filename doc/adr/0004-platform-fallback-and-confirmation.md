# 区分平台能力的降级与确认

- Android 刷新率选择和 Windows Skia raster 缓存预算是优化，不是启动条件。通道失败时记录错误，保留系统显示模式或引擎默认预算并继续启动。Skia 预算约束的是 raster scratch 高水位，不是图片/IO 纹理、视频输出或进程总内存。入口见 [`platform_setup.dart`](../../lib/app/platform_setup.dart)。
- 初始化播放偏好时，未知网络可以保守地按非 Wi-Fi 处理；显式保存按网络区分的偏好时必须确认网络类型，不能把探测失败当作非 Wi-Fi，否则会改写错误的偏好档。入口见 [`connectivity.dart`](../../lib/platform/network/connectivity.dart)。
- 打包目录只有在所有要求的资源都存在时才能直接使用；否则走逐文件暂存再替换，仅在所有资源准备完成后向调用方交付目录。复制失败保留原始异常并允许重试，不交付一个缺文件的目录，也不承诺跨文件的事务回滚。入口见 [`bundled_assets.dart`](../../lib/platform/files/bundled_assets.dart)。
