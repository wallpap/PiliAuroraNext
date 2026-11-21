# 统一 Windows 开发和打包的运行布局

Windows 开发使用和安装包一致的就地布局；Visual Studio 默认构建也执行安装，而不是另造一份仅用于调试的 bundle。顶层的 `BINARY_NAME` 同时供 Flutter 和 runner 使用；安装前缀必须先于生成插件规则设置，因为插件在配置阶段读取该前缀。每次安装完整替换 Flutter 资产目录，以免已从构建输入删除的资产继续留在输出里。入口见 [`windows/CMakeLists.txt`](../../windows/CMakeLists.txt)。

标准编译设置同时被应用和插件复用；兼容某个插件的 MSVC 诊断设置留在那个目标上，不降低整个应用的告警强度。runner 定义 `NOMINMAX`，避免 Windows 头文件宏干扰标准库 API，并依赖 `flutter_assemble` 生成运行时所需资产。入口见 [`windows/runner/CMakeLists.txt`](../../windows/runner/CMakeLists.txt)。

升级覆盖旧版本时，Restart Manager 可以关闭拒绝会话结束或仍驻留托盘的进程；文件清理以旧清单和现存内容的摘要共同判定所有权，保留用户修改过的文件。入口见 [`inno_setup.iss`](../../windows/packaging/exe/inno_setup.iss)。
