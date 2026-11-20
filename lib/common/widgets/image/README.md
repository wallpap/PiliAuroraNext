# 图片模块

普通图片沿用 Flutter Provider 生命周期，正文与预览由内容会话管理视口和资源。行为回归与原生测试前提见[测试契约](../../../../test/common/widgets/image/CONTRACTS.md)。

## 入口与所有权

| 入口 | 职责 |
| --- | --- |
| `cached_image.dart` | CachedImage、CachedImageProvider、LocalImageProvider、框架 decoder callback 和 ImageCache 协作；保留默认 Provider 相等性及外层 ResizeImage |
| `content_image.dart` | 订阅、加载/动画需求、稳定源几何、显示会话；`image_viewer/content_viewer.dart` 适配手势视口 |
| `image_resources.dart` | binding 内共享调度，默认两项原生并发、最多一项重预处理，可见优先、owner 轮转与等待老化；测试用 runWith 隔离，runtime 身份不进入 Provider 键 |
| `src/image_source_store.dart`、`src/image_sampling.dart` | 不可变快照租约；按实际元信息、BoxFit 和有效 DPR 推导采样，尺寸向上归档 |

`loadImageFrame(File)` 返回 result/cancel/drained。result 是调用者独占的第 0 帧，使用后 dispose；codec 取帧后关闭。取消保留原生名额到真实完成，迟到图像由请求释放。`loadNetworkImageFrame` 合并编码文件读取后复用此流程；isCurrent 在取得文件和准入后检查弹幕期限。

Provider 的图像由 ImageStream/ImageInfo 管理，消费者释放自己的 ImageInfo。ContentImage 在绘制结束后释放替换的旧帧，动画和无监听缓存交接由同一私有 completer 管理。ImageLoadingScope 与 TickerMode 独立，允许静态导出；Gallery 邻页可加载，只有当前页播放动画。正文滚动时计算祖先裁剪交集，静态头像不做全局逐帧扫描。

sourceSize 仅作布局提示，实际 decoder 原始尺寸优先；ResizeImage 的缩小帧不作为原始元信息。cover 在 decoder callback 内按真实比例采样，不新增预探测 codec。未知比例的 CDN 请求保留来源，可能下载更多编码字节。

雪碧图保留原坐标和 3 项/24MiB 缓存，弹幕保留期限与任务/字节配额及文本降级。图片表情使用惰性网格并播放动画，文字和混合历史保留 Wrap。通知封面由音频插件单独配置为 512×512，不占 Dart 解码队列。

## 区域协议与门控

Windows 的 ContentImage 有交互视口、未指定缩小目标且来源为网络缓存或本地文件时，选择同目录的 `piliauroranext_image_worker.exe`，目前用于 Gallery。worker 缺失、普通正文、封面和其他平台均走完整帧。

`src/native_worker_backend.dart` 为每份不可变来源启动独立 CPU worker：WIC 处理静态 JPEG/PNG，固定 libwebp decoder 处理静态 WebP。有界管道输出预乘 RGBA，由普通 `ui.Image` 绘制；没有外部 GPU 纹理或 raw 临时文件。来源租约保留到进程退出，隐藏、换源、取消和错误关闭均等待排空；`imageRegionWorkers` 记录进程数。

会话预算、基础层上限和共享输出预算分别约束保留像素及在途预留。通用配置见 `src/region_content_session.dart`，Gallery 覆盖值见 `content_image.dart`，共享预算见 `image_resources.dart`。显示交接期间的新旧图像和待绘制退役图像也须计费。

基础层采样足够时省去细节，放大后合并可见矩形并补充 1:1 区域。`RegionImageSurface` 对基础与细节互斥裁剪，避免半透明像素重复混合。旧图先从显示状态移除，绘制后再释放根句柄；任务持独立来源租约。滤镜、颜色和源坐标保持稳定。

文件签名提前排除 GIF 等非 JPEG/PNG/WebP 来源，省去快照和 worker；候选格式中的动画、EXIF 方向和超容量视口明确回退。WebP 全局缩放中间层超过 40MiB，或 WIC 返回颜色配置无效（`0x800707DB`）时，也先排空 worker 再交给 Flutter 完整帧解码。损坏或其他进程异常保留错误状态并释放会话，诊断记录原生错误阶段和错误码。

ImageSourceStore 目录由 CacheManager.imageSources 提供。普通完整帧不复制快照；最后来源/任务租约结束后删除快照。clear 保留活动文件，清理失活及遗留条目。诊断仅记录计数，避免明文路径和 URL。

## 验证边界

用例、命令及各阶段的像素、生命周期、能力回退和打包结果见[测试说明](../../../../test/common/widgets/image/CONTRACTS.md)。

性能对照须固定源码、输入、物理视口与缓存条件，同时记录进程树峰值和可见延迟。模块输出预算不能证明进程总内存或延迟满足要求。

其他 GPU/驱动、Android、完整应用长期运行及通知原生缓存仍待设备验证。输出预算不包含全部解码工作区，完整帧回退仍可能产生大图峰值。跨 surface 区域去重、Android 原生区域后端和第二套通用像素 LRU 尚未实现；弹幕重复静态表情仍由各消费者各建 codec。
