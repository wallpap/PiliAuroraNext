# 图片测试契约

图片入口与所有权见[图片模块](../../../../lib/common/widgets/image/README.md)。测试使用本地夹具与真实 `ui.Image`，不依赖用户日志或网络；受控 decoder 验证请求和释放协议，原生像素与设备性能另行验证。

## 自动化契约

测试集中在本目录，跨入口回归按[测试目录](../../../README.md)定位。修改时按影响选择以下行为：

- 来源和调度：不可变快照、共享租约、有界并发、取消后等待真实完成、错误原因与关闭排空。
- 帧与采样：一次性第 0 帧、codec 和图像所有权、decoder callback、BoxFit/DPR、动画及框架缓存生命周期。
- 内容与视口：稳定源几何、加载与动画许可、迟到结果隔离、滚动、缩放和窗口变化。
- 区域后端：基础层与细节交接、跨会话预算、能力回退、真实显示像素、来源释放和 worker 退出。
- 生产入口：本地与网络图片、Provider 与 CSS 标记、普通表情、正文、Gallery、雪碧图及弹幕。

## 必须保留的已有回归

按变更复用生命周期、动画恢复、ImageCache、首帧、decoder callback、ResizeImage、裁剪 URL 和 retained layer 用例，以及播放器 `preview_image_cache_test.dart`、直播 `emote_danmaku_test.dart`、普通表情控制器和受影响页面。

直接 Provider、CSS 列表标记、本地封面/附件、雪碧图及弹幕需覆盖真实接线。表情回归以真实 ScrollPosition 到达末尾并点击末项，保持 600 个候选中少于 100 个活动/邻域条目及选择语义。单帧 Provider 与 12 帧动画消费者分别建夹具，首帧交付不绑定动画时钟。

## 区域后端和设备验收

Windows Gallery 使用 WIC 静态 JPEG/PNG 与 libwebp 静态 WebP。受控后端测试预算、层级和交接协议，真实 worker 测试像素、接线、来源释放及进程排空。

Windows 先生成确定性夹具并构建 worker：

```powershell
uv sync --locked
uv run --locked python tool/probes/windows/image_region_probe.py
uv run --locked python -m unittest discover -s tool/probes/windows -p image_region_probe_test.py -v
pwsh -NoProfile -File tool/run-ci-tests.ps1 -NativeImages -Concurrency 2
```

构建产物在 `build/probes/image-region/`。要使用其他位置，可设置 `REGION_TEST_WORKER` 和 `REGION_FIXTURES`。普通主机测试找不到 Windows worker 时会跳过原生用例。专用 CI 步骤设置 `REGION_TEST_REQUIRED=1`，找不到 worker 或夹具清单就会失败。

固定 libwebp 来源和裁剪修复见[上游登记](../../../../third_party/libwebp/UPSTREAM.md)。

缺少 WIC codec 的格式回退完整帧，并与独立 Flutter 解码参照比较。当前 Windows 引擎也不支持测试 AVIF 夹具，回退保留同样的格式错误。

性能解释见[图片模块验证边界](../../../../lib/common/widgets/image/README.md#验证边界)。设备验证覆盖：

- 一般/高/超高/低分辨率、GIF、长图、动画 WebP、EXIF 方向、透明边界与接缝。
- 文章和私信阅读、网格预览、本地文件、翻页缩放拖动、窗口变化、离页和重复循环。
- 通知封面与 Bitmap 缓存、快捷方式、视频交接、截图及离屏导出的矩形完整性。
- 固定来源、物理视口、滤镜和缓存条件，比较冷热首屏、帧时间、真实峰值、退出资源与磁盘；未测 native/GPU 成本保留未知。
