# 分离 Windows 窗口可见性与播放就绪

- 独立播放器先渲染 Flutter 加载界面，首帧后显示窗口，并通过现有路由交付播放参数以保留导航观察器的初始化顺序。远端流和视频纹理不阻塞窗口首次显示；稳定纹理仍是声音交接和剩余启动等待的条件。入口见 [`desktop_playback_launch.dart`](../../lib/app/desktop_playback_launch.dart) 和[首帧流程](../development/runtime-flows.md#原生加载首帧与释放)。
- 主窗口和播放窗口使用同一套可见性判断，不把 `inactive`（失焦）作为不可见：其他播放窗口仍可能在屏幕上。从最小化直接恢复到最大化时，Windows 可能只报告 `maximize`，所以不能只监听 `restore`。`hidden`、`paused` 禁止普通帧，需强制提交一次 `TickerMode` 更新，让子树及时停止视觉订阅和释放显示资源。入口见 [`window_visibility.dart`](../../lib/platform/desktop/window_visibility.dart) 和 [`desktop_theme.dart`](../../lib/app/desktop_theme.dart)。
- 主窗口的自绘标题栏在路由外，提示浮层覆盖整个窗口，避免提示越过栏底时被页面遮挡。Windows 无须额外同步系统标题栏亮暗；关闭按钮仍发普通关闭事件，由已有流程决定托盘驻留或释放播放器。Flutter 合成背景与 GDI 背景擦除使用同一颜色；主题和全屏切换串行下发，避免两个层在切换时采用不同的背景。入口见 [`desktop_title_bar.dart`](../../lib/app/desktop_title_bar.dart) 和 [`window_background.dart`](../../lib/platform/desktop/window_background.dart)。
