# 播放业务入口

- `application/subtitle_sources.dart` 按视频页面持有字幕缓存，导出使用打开对话框时的快照；切集后不提交旧缓存。`data/subtitle_repository.dart` 读取远端字幕并保留原始 JSON 导出。
- `application/video_metadata.dart` 查询互动节点和弹幕趋势；互动分支只接受当前媒体的最新请求。
- `application/seek_preview_timeline.dart` 为同一播放来源共用预热和拖动请求。松手隐藏预览，切源取消请求并清空快照。`data/seek_preview_repository.dart` 负责远端协议，展示层消费已定位到裁剪格的帧并持有图片资源。
- `application/video_danmaku_interactions.dart` 接受当前账号和视频的点赞查询、点赞、撤回、举报与发送。过期点赞查询不覆盖确认写入；确认撤回才移除显示项；举报成功和附加屏蔽结果分别结算。点播菜单、弹幕列表和直播聊天复用 `presentation/` 的弹幕操作。
- `application/danmaku_block.dart` 管理主账号的屏蔽规则查询和串行写入。页面将已确认规则应用到当前播放器。HTTP 映射和本地缓存归 `data/`，保留 Hive 的类型编号和字段布局。无法编译的服务端正则仍可查看和删除，其余有效规则继续生效。
- `application/audio_media.dart` 解析音频媒体源，传输协议、音轨与音量字段映射留在 `data/`。
- `application/live_chat_connection.dart` 持有直播消息流、连接代次和凭据缓存；房间切换释放旧连接，页面仍管理聊天列表及滚动。

这里不持有原生播放器。视频和直播继续使用 `PlaybackOwner`，独立音频沿用原生释放屏障，详见[播放状态模型](../../../doc/development/playback-model.md)。实际媒体输出、聊天室连接和设备交互仍需在目标设备验收。
