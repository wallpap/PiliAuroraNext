# 默认构建与策略

`tool/build.ps1` 默认构建 Release，自动使用 `third_party/flutter_engine/prebuilt/` 的固定引擎。本地和发布 CI 采用相同的引擎材料、身份协议和应用默认策略，日常构建无需传入引擎路径或额外的呈现定义。命令、签名和输出见[构建与测试](build-and-test.md#构建)。

## 构建契约

| 入口 | 引擎与输出 |
| --- | --- |
| Windows 默认 Release | `windows-x64`，呈现配置 `windowsDwmPaced`；运行目录附引擎身份，打包配置自动生成 |
| Android 默认 Release | `android-arm`、`android-arm64`、`android-x64`，呈现配置 `androidFramePlan`；默认生成三个分 ABI APK，`-Abi` 选择一个架构 |
| Android 独立测试包 | 同一 arm64 Release 引擎与 `.dev` 包名，使用本机 Release 签名 |
| 显式 Debug | FVM SDK 的调试引擎，呈现配置 `standard`；适合断点与热重载 |
| 引擎维护 Profile | 独立编译同模式引擎后验证；维护流程见[引擎工具](../../tool/engine/README.md#修改引擎) |

Flutter 与引擎提交、模式、架构、补丁和 overlay、二进制摘要、原生回归状态均须匹配。身份校验失败终止构建。直接调用 Flutter 构建会绕过装配；引擎相关验收使用项目入口。引擎版本和许可证集中在[预编译引擎](../../third_party/flutter_engine/README.md)。

## 策略入口

默认值与启用条件在对应配置中维护。核对行为时沿下列入口查看，用户已保存的偏好按各设置的生效时机使用。诊断实验的结果与生产配置分别记录。

| 领域 | 核对内容 | 源码与维护入口 |
| --- | --- | --- |
| Windows 呈现 | 支持探测、相位校准、呈现队列与失败回退 | [Windows 引擎](../../tool/engine/windows_frame_pacing/README.md#呈现与计时) |
| Android 呈现 | 帧计划身份、纹理合并、EGL 输出与普通调度回退 | [Android 引擎](../../tool/engine/frame_plan/README.md#输出流程) |
| Windows 图形资源 | 窗口 raster 预算、ANGLE 上传策略、外部纹理导入与释放 | [架构](architecture.md#桌面窗口与标题栏)、[Windows 引擎](../../tool/engine/windows_frame_pacing/README.md) |
| 视频资源交接 | 媒体卸载、首帧确认、降画质和超分重建的顺序 | [播放状态模型](playback-model.md)、[Windows 输出](../maintenance/windows-video-output.md) |
| 点播缓存 | 默认策略、前后向预算、倍速换算及下一次加载的配置捕获 | [设置行为](settings-behavior.md)、[缓存策略](../../lib/plugin/pl_player/models/video_buffer_policy.dart)、[偏好](../../lib/services/settings/stored_preferences.dart) |
| Windows Gallery | 格式支持、区域预算、worker 生命周期与能力回退 | [图片模块](../../lib/common/widgets/image/README.md)、[测试契约](../../test/common/widgets/image/CONTRACTS.md) |
| 弹幕 | 来源配额、候选选择、显示窗口与图片工作集的独立预算 | [架构](architecture.md#弹幕显示与来源)、[功能入口](features.md#弹幕合并与调度)、[密度对照方法](../../tool/experiments/README.md#配置选择) |

弹幕候选限制见 [`priority.dart`](../../lib/pages/danmaku/priority.dart)，显示窗口见 [`timeline_window.dart`](../../lib/pages/danmaku/timeline_window.dart)，来源缓存见 [`cache.dart`](../../lib/pages/danmaku/cache.dart)。

缓存由时长和字节共同限制，倍速仅换算时长。Windows 固定 libmpv 支持字节补读阈值；Android 不传该选项。缓存预算分别约束各 demuxer，图片、Skia、视频纹理和驱动内存同样分别计量。
