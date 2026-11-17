# 项目文档

下载与更新见[中文 README](../README.md#适配平台与下载)；另有 [English README](../README.en.md)。详细指南以中文提供。

版本记录见[更新日志](../CHANGELOG.md)；`1.0.0` 为迁移至 PiliAuroraNext 后的首个版本。

## 使用指南

| 任务 | 文档 |
| --- | --- |
| 独立播放窗口、音量、弹幕、空降助手 | [播放与弹幕](guides/playback.md) |
| 黑名单、评论等级、点赞、评论菜单、表情包 | [内容过滤与互动](guides/content.md) |
| 账号与设置导入导出、WebDAV、本机数据 | [账号与设置备份](guides/data-security.md) |
| 提交问题或性能记录 | [问题反馈](../README.md#问题反馈) |

## 开发

首次开发先完成[环境配置与构建](development/build-and-test.md)，已有环境直接按任务查阅。Agent 遵循根目录 [AGENTS.md](../AGENTS.md)。

| 任务 | 文档 |
| --- | --- |
| 定位功能、源码与测试入口 | [功能领域地图](development/features.md) |
| 理解模块、平台边界和术语 | [架构](development/architecture.md)、[架构图](diagrams/README.md) |
| 追踪启动、请求、播放、下载、消息 | [运行流程](development/runtime-flows.md) |
| 修改账号、状态、分页或异步结果 | [状态管理](development/state-management.md)、[账号拦截器](../lib/utils/accounts/account_manager/README.md) |
| 修改播放状态、原生输出与释放 | [播放状态模型](development/playback-model.md)、[Windows 视频输出](maintenance/windows-video-output.md) |
| 修改图片加载、交互预览与资源释放 | [图片模块](../lib/common/widgets/image/README.md)、[图片测试契约](../test/common/widgets/image/CONTRACTS.md) |
| 核对设置的生效时机 | [设置行为](development/settings-behavior.md) |
| 修改桌面标题栏与提示浮层 | [桌面窗口与标题栏](development/architecture.md#桌面窗口与标题栏) |
| 修改下载、离线列表或任务生命周期 | [下载模块](../lib/features/download/README.md) |
| 修改共享账号资料、个人中心或无痕角色 | [账号模块](../lib/features/account/README.md) |
| 修改首页推荐、视口补位、作者过滤或推荐偏好 | [内容发现模块](../lib/features/content_discovery/README.md) |
| 修改动态作者、分类、小站、表情或投票/预约编辑 | [社区模块](../lib/features/community/README.md) |
| 修改订阅列表、合集详情或失效清理 | [订阅模块](../lib/features/subscriptions/README.md) |
| 修改消息、私信、未读或分享 | [消息模块](../lib/services/messaging/README.md) |
| 运行检查、构建或制作发布包 | [构建与测试](development/build-and-test.md)、[测试目录](../test/README.md)、[工具入口](../tool/README.md) |
| 核对默认引擎、缓存与资源策略 | [默认构建与策略](development/build-defaults.md) |
| 更新依赖或定制引擎 | [第三方依赖](../third_party/README.md)、[引擎差异](development/engine-patches/README.md)、[引擎工具](../tool/engine/README.md) |
| 排查设备、性能与内存问题 | [维护与排障](maintenance/troubleshooting.md)、[探针](../tool/probes/README.md)、[实验](../tool/experiments/README.md) |

## 维护与历史

- [历史排障经验](diagnostic-notes/README.md)保留可复用的排查方法；当前采用项见[默认构建与策略](development/build-defaults.md)。本地 `doc/dev/` 保存专题摘要、必要报告与独有材料，可再生的编译产物和采集临时输出放在 `build/`，整理方式见[实验资料归档](../tool/experiments/README.md#实验资料归档)。
- 依赖维护见[第三方依赖](../third_party/README.md)。来源、许可证与定制修订保留在登记和各包的 `UPSTREAM.md` 中。

## 维护文档

公开文档保留用户操作、开发流程、模块边界、设计原因和行为约束。用户指南说明入口、生效时机与失败后的操作；开发指南提供源码入口和验证方法；agent 入口按任务链接所需上下文。

版本、默认值、依赖清单和 CI 选中文件直接引用配置或脚本。具体用例查看测试源码，模块契约放在代码旁；索引只负责导航，避免重复维护实现细节。

迁移计划与进度、逐文件盘点、设计草稿、单次测试数字、性能对照和设备报告放在本地 `doc/dev/`，该目录由 Git 忽略。原始日志和可再生产物放在 `build/`。稳定结论提炼为约束或排查方法后再进入公开文档，并保留适用范围；许可证、上游来源和兼容性要求随源码维护。

公开导航只链接 Git 跟踪的资料。移动或合并文档时同步更新引用，检查相对链接和标题锚点。行为、接口或操作流程变化时更新对应文档，日常代码调整无需另写进度记录。
