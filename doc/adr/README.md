# 架构决策记录

| 记录 | 决策 |
| --- | --- |
| [0001](0001-lazy-windows-webview.md) | 延迟创建 Windows WebView 环境 |
| [0002](0002-windows-window-presentation.md) | 分离 Windows 窗口可见性与播放就绪 |
| [0003](0003-startup-failure-and-diagnostics.md) | 让启动故障可报告且不暴露原始异常正文 |
| [0004](0004-platform-fallback-and-confirmation.md) | 区分平台能力的降级与确认 |
| [0005](0005-windows-runner-install-layout.md) | 统一 Windows 开发和打包的运行布局 |
| [0006](0006-tex-for-plain-text-comments.md) | 在纯文本评论中降级呈现 TeX |
| [0007](0007-android-platform-integration.md) | 通过系统边界接入 Android 能力 |
| [0008](0008-shared-action-cooldowns.md) | 冷却窗口独立于异步动作完成 |
| [0009](0009-http-protocol-ownership.md) | 路由表与请求协议分开维护 |
| [0010](0010-windows-runner-ownership.md) | Windows runner 管理原生窗口和平台资源 |
| [0011](0011-windows-diagnostics-snapshots.md) | Windows 诊断采样只发布聚合快照 |
| [0012](0012-image-region-decoder-fallback.md) | Windows 区域解码受限时回退完整帧 |
| [0013](0013-test-observable-boundaries.md) | 用独立观察验证异步和绘制边界 |
