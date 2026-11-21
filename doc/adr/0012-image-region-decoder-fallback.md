# Windows 区域解码受限时回退完整帧

区域 worker 通过 WIC/libwebp 读取有界区域，持续会话保留源和解码工作区；粗层从同一全局缩放结果裁切，避免独立缩放每块造成采样相位差，并为粗层临时像素单独限额。

遇到不支持的方向、系统缺少 WIC codec 或 WIC 拒绝 ICC 配置时，不把能力缺失当作损坏，也不忽略方向或色彩。结束原生尝试后由 Flutter 完整帧路径接管。入口见 [`image_worker.cc`](../../windows/image_worker/image_worker.cc) 和[图片模块](../../lib/common/widgets/image/README.md)。
