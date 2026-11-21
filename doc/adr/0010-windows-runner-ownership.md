# Windows runner 管理原生窗口和平台资源

窗口创建时按目标显示器把逻辑尺寸换算成物理像素，并让 Flutter surface 从实际客户区尺寸启动，避免初次显示不必要的表面销毁与重建。创建和显示分开；背景只由 GDI 填充 Flutter 尚未覆盖的区域，并遵循主题和全屏颜色。保留旧 Windows SDK 的 DWM 属性常量和 PerMonitor V1 所需的动态缩放入口。

窗口和插件析构完再反初始化 COM，包括 `S_FALSE` 的成功初始化。原生控制器释放前先打断成员引用，避免插件退出重入访问半析构对象。更新退出走专门消息，通知 Dart 保存进度和释放播放器，而不是遵循普通关闭的托盘设置。主窗口和播放子进程共享任务栏应用标识；解码测试子进程把驱动崩溃交给父进程记录，不让系统错误对话框阻塞验收。

入口见 [`main.cpp`](../../windows/runner/main.cpp)、[`flutter_window.cpp`](../../windows/runner/flutter_window.cpp) 和 [`win32_window.cpp`](../../windows/runner/win32_window.cpp)。
