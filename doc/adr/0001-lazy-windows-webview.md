# 延迟创建 Windows WebView 环境

不把 WebView2 就绪纳入普通应用启动的前置条件。Windows 启动只登记数据目录，不在请求初始化时同步 WebView Cookie；首次打开网页、验证码或执行显式 Cookie 操作时才等待共享环境。这样非网页启动路径不承担 WebView 初始化，代价是第一次网页操作必须等待环境就绪。

普通网页须在加载前同步当前账号 Cookie；显式操作等待环境就绪后复核账号，避免把等待前的账号状态写进共享环境。非 Windows 平台继续沿用平台自己的网页环境。入口见 [`platform_setup.dart`](../../lib/app/platform_setup.dart)、[`bootstrap.dart`](../../lib/app/bootstrap.dart) 和[应用启动流程](../development/runtime-flows.md#应用启动)。
