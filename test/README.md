# 测试目录

从仓库根目录使用 FVM 运行测试。环境、Flutter 补丁和构建前提见[构建与测试](../doc/development/build-and-test.md#静态检查与测试)。

## 运行范围

```powershell
fvm flutter test
pwsh -NoProfile -File tool/run-ci-tests.ps1
```

第一条运行 `test/` 下的所有套件。第二条是 CI 用的脚本，自动发现共享测试，按[平台分类](../tool/test-platforms.json)选择当前主机还要运行的套件。加 `-List` 可查看选中的文件。PR 分工见[工作流](../.github/workflows/checks.yml)。

新增共享测试不用登记。依赖 Windows 补丁、Android 模拟通道或真实区域解码器的套件要登记；需要在两种主机上分别验证实际平台行为的套件也要登记。桌面音量迁移和图形内存采样读取实际操作系统，所以 CI 只在 Windows 上运行这些测试。Flutter 的模拟目标平台无法进入这些分支。

定位单个功能时，将相应文件或目录传给 `fvm flutter test --no-pub`。先验证直接受影响的行为，再按公共接口或平台影响扩大范围。原生或设备探针见[探针目录](../tool/probes/README.md)，按需对照见[实验目录](../tool/experiments/README.md)。

## 目录与夹具

| 目录 | 范围 |
| --- | --- |
| `architecture/` | 依赖政策、模块边界与工作流约束 |
| `app/`、`router/` | 启动、窗口与路由生命周期 |
| `features/` | 领域查询、写入及跨入口状态 |
| `pages/` | 页面交互、异步结果消费与释放 |
| `common/widgets/` | 通用控件、图片与手势 |
| `http/`、`grpc/` | 协议解码、请求转换、账号与重试策略 |
| `plugin/pl_player/` | 播放会话、媒体源、原生输出与资源交接 |
| `services/` | 跨页面服务、消息、诊断与平台能力 |
| `core/` | 独立 Dart 基础能力 |
| `utils/` | 存量行为回归，覆盖账号、存储、平台及共享界面 |
| `support/` | 跨领域复用的测试辅助工具 |

用例以 `_test.dart` 结尾，具体覆盖直接查看文件中的测试名称。功能与测试入口见[功能地图](../doc/development/features.md)，领域约束见各模块 README。

领域专用 fixture 与调用者放在同一目录。Hive 内存读写可复用 `support/memory_box.dart`；挂起 HTTP 响应可复用 `support/controlled_http_adapter.dart`、`support/controlled_interceptor.dart`，等待真实请求到达后再提交响应。

合并或替换用例时保留账号隔离、确认写入、分页重试和资源释放等边界，预期结果须独立于被测实现。异步用例优先等待请求或完成事件，计时边界使用模拟时钟。`testWidgets` 中持续创建 Timer 的对象须在用例体结束前释放，外层 `tearDown` 晚于测试绑定的计时器检查。

列表刷新在 `features/content_discovery/discovery_listing_test.dart` 验证，通用内容库视图在 `features/content_library/feed_view_test.dart` 验证。订阅等页面的测试检查实际接线和各自的游标、标题、选择和滚动。用可见内容和滚动位置判断页面是否保持原样，无须比较 Element、控制器或集合是不是同一个对象。

## 平台前提

Windows 主机首次测试或从 Android 环境切回后，先应用 Windows Flutter 补丁：

```powershell
pwsh -NoProfile -File lib/scripts/patch.ps1 windows -SkipPubGet
```

依赖须提前准备。隐藏页面语义与绘制资源回收测试依赖这些补丁，不能在 Android 补丁状态下判断结果。

### 图片与页面保活

图片原生回归须先准备确定性夹具和 worker，命令见[图片测试契约](common/widgets/image/CONTRACTS.md#区域后端和设备验收)。缺少 worker 或主机能力导致的跳过须单独记录。隐藏页面资源回归位于 `common/widgets/` 及图片目录，须在应用上述 Windows 补丁后运行。

内存验收分别记录模块引用、原生资源与进程指标；弱引用回收或资源计数归零不能代替进程峰值与长期测量。

### 播放会话与平台输出

播放会话与输出回归位于 `plugin/pl_player/`，反例构造见[状态模型](../doc/development/playback-model.md)。模拟 Player 和通道检查命令、身份与释放屏障，原生呈现和声音使用目标设备探针验证。

真实 WebView、Cookie、GPU、MediaCodec、声音、全屏和系统窗口仍需设备验证。消息验证见[消息模块](../lib/services/messaging/README.md#验证)。
