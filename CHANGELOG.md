# 更新日志

本日志从 PiliAuroraNext 的独立版本序列开始记录。迁移前的版本与提交历史保留在 [PiliAurora 原仓库](https://github.com/wallpap/PiliAurora)，安装包与发布状态见 [PiliAuroraNext Releases](https://github.com/wallpap/PiliAuroraNext/releases)。

## 1.1.2 — 2026-11-22

- 评论等级过滤会保留 UP 主发布的评论，以及被 UP 主回复过的评论；设置页也补充了这条规则的说明。
- 修复首次加载视频时未应用默认播放倍速的问题。
- 修复部分哔哩哔哩移动网页的“打开 App”链接无法进入对应视频的问题，并支持按唤起链接中的分 P 定位。

## 1.1.1 — 2026-11-21

- 更新弹窗支持显示 Markdown 格式的发布说明。
- 减少首页推荐列表在加载和分页时的卡片渲染开销。
- 减少重复图片解码，优化 Windows 大图预览的 WebP 缩放。
- 修复 Windows 图片解码进程退出时偶发的管道错误。

## 1.0.0 — 2026-11-16

迁移至 PiliAuroraNext 后的首个版本，建立新仓库的发布基线。

- 应用名称统一为 PiliAuroraNext，Android 应用 ID 为 `com.wallpap.piliauroranext`，使用独立的应用标识与数据目录。
- 承接迁移时已有的视频、番剧、直播、动态、私信、离线下载、Windows 独立播放窗口、弹幕合并和内容过滤功能。
- 保留既有定制依赖及固定引擎，本地定制依赖从 `+piliauroranext.1` 开始计数，继续保留版权、许可证与上游来源记录。
- 发布目标为 Android（`arm64-v8a`、`armeabi-v7a`、`x86_64`）和 Windows x64（安装版与便携版），统一使用 `1.0.0+构建号`，构建号由新仓库提交数生成。

迁移说明与下载入口见[中文 README](README.md#仓库迁移说明)，构建与发布流程见[开发文档](doc/development/build-and-test.md#发布构建与附件)。
