# 测试目录

从仓库根目录使用 FVM 运行测试。环境、Flutter 补丁和构建前提见[构建与测试](../doc/development/build-and-test.md#静态检查与测试)。

## 运行范围

```powershell
fvm flutter test
pwsh -NoProfile -File tool/run-ci-tests.ps1
```

第一条运行 `test/` 下的业务测试；第二条运行 CI 选定的共享与当前主机回归。选中文件、平台条件和排除项以[CI 测试脚本](../tool/run-ci-tests.ps1)为准，PR 分工以[工作流](../.github/workflows/checks.yml)为准。调整范围时检查目录与文件是否重叠，避免重复执行。

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
| `utils/` | 工具函数、存储及账号状态 |
| `support/` | 跨领域复用的测试辅助工具 |

用例以 `_test.dart` 结尾，具体覆盖直接查看文件中的测试名称。功能与测试入口见[功能地图](../doc/development/features.md)，领域约束见各模块 README。

领域专用 fixture 与调用者放在同一目录。Hive 内存读写可复用 `support/memory_box.dart`；挂起 HTTP 响应可复用 `support/controlled_http_adapter.dart`、`support/controlled_interceptor.dart`，等待真实请求到达后再提交响应。

合并或替换用例时保留账号隔离、确认写入、分页重试和资源释放等边界，预期结果须独立于被测实现。异步用例优先等待请求或完成事件，计时边界使用模拟时钟。`testWidgets` 中持续创建 Timer 的对象须在用例体结束前释放，外层 `tearDown` 晚于测试绑定的计时器检查。

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
