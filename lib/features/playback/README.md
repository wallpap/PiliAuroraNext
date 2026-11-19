# 播放业务入口

- `application/subtitle_sources.dart` 按视频页面持有字幕缓存，导出使用打开对话框时的快照；切集后不提交旧缓存。`data/subtitle_repository.dart` 读取远端字幕并保留原始 JSON 导出。
- `application/video_metadata.dart` 查询互动节点和弹幕趋势；互动分支只接受当前媒体的最新请求。
- `application/audio_media.dart` 解析音频媒体源，传输协议、音轨与音量字段映射留在 `data/`。
- `application/live_chat_connection.dart` 持有直播消息流、连接代次和凭据缓存；房间切换释放旧连接，页面仍管理聊天列表及滚动。

这里不持有原生播放器。视频和直播继续使用 `PlaybackOwner`，独立音频沿用原生释放屏障，详见[播放状态模型](../../../doc/development/playback-model.md)。实际媒体输出、聊天室连接和设备交互仍需在目标设备验收。
