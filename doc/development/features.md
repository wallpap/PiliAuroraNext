# 功能领域地图

页面路径相对 `lib/pages/`，API 路径相对 `lib/http/`。从 `lib/router/app_pages.dart` 找路由，沿页面的 import 追踪服务和模型。模块边界见[架构](architecture.md)，异步结果见[状态管理](state-management.md)，时序见[运行流程](runtime-flows.md)。

## 代码与测试入口

| 领域 | 页面 | API/服务/模型 | 回归入口 |
| --- | --- | --- | --- |
| 主导航与角标 | `main/`、`home/`、`mine/` | `lib/features/app_shell/`、`lib/services/settings/navigation_preferences.dart` | `test/pages/main/` |
| 首页、热门、排行、PGC 索引 | `home/`、`hot/`、`rank/`、`popular_*`、`pgc_index/` | [内容发现模块](../../lib/features/content_discovery/README.md) | `test/features/content_discovery/`、`test/pages/member_feed/` |
| 搜索 | `search*`、`member_search/`、`live_search/` | [搜索模块](../../lib/features/search/README.md) | `test/pages/search/`、`test/pages/search_results/`、`test/pages/scoped_search/` |
| 视频、文章、番剧、音频 | `video/`、`article/`、`article_list/`、`pgc/`、`audio/`、`music/` | `video.dart`、`pgc.dart`、`music.dart`、`reply.dart` | `test/pages/video/`、`test/pages/article/`、`test/pages/pgc/`、`test/pages/audio/` |
| 播放器与原生输出 | 页面通过 `PlaybackOwner` 提交计划及命令 | `lib/plugin/pl_player/playback/`；`playback_contracts.dart`、`playback_session.dart`、`native_playback_runtime.dart` | `test/plugin/pl_player/`、`tool/probes/playback/` |
| 弹幕与评论 | `danmaku/`、`danmaku_block/`、`main_reply/`、`my_reply/`、`video/reply/` | `danmaku.dart`；[评论模块](../../lib/features/community/README.md#评论) | `test/pages/danmaku/`、`test/pages/danmaku_block/`、`test/pages/community/` |
| 表情包 | `emote/`、`live_emote/`；管理在 `emote/manage.dart`、`preview.dart` | [社区模块](../../lib/features/community/README.md)；评论包、直播包与最近历史 | `test/pages/emote/`、`test/pages/live_emote/`、`test/pages/community/` |
| 直播 | `live/`、`live_room/`、`live_follow/`、`live_search/`、`live_dm_block/` | `live.dart`；`lib/services/live_stream/` | `test/pages/live/`、`test/pages/live_room/`、`test/pages/live_follow/` |
| 账号、登录、会员 | `login/`、`login_devices/`、`log_table/`、`member/`、`member_profile/` | `login.dart`、`member.dart`、`member_profile.dart`、`user.dart`；[共享账号资料与个人中心](../../lib/features/account/README.md)、`lib/utils/accounts/` | `test/pages/login/`、`test/pages/account_queries/`、`test/pages/member_profile/`、`test/features/account/`、`test/utils/accounts/` |
| 动态、小站、投票与预约 | `dynamics/`、`dynamics_tab/`、`bubble/`、`dynamics_create_vote/`、`dynamics_create_reserve/` | [社区模块](../../lib/features/community/README.md)；作者/分类查询、发布失效与独立编辑草稿 | `test/features/community/`、`test/pages/dynamics/`、`test/pages/bubble/` |
| 个人空间 | `member/`、`member_contribute/`、`member_video/`、`member_video_web/`、`member_favorite/` | [个人空间模块](../../lib/features/member_space/README.md)；空间主查询、投稿和收藏 | `test/pages/member/`、`test/pages/member_favorite/`、`test/pages/member_pgc/` |
| 空间动态与互动名单 | `member_dynamics/`、`dynamics_detail/`、`common/dyn/like_list/`、`common/dyn/repost_list/` | [社区模块](../../lib/features/community/README.md#动态)；空间查询、共享删除/置顶、惰性名单与计数 | `test/pages/dynamics/management_results_test.dart`、`test/features/community/dynamic_activity_test.dart` |
| 话题浏览与发布选择 | `dynamics_topic/`、`dynamics_topic_rcmd/`、`dynamics_select_topic/`、`dynamics_mention/` | [话题与发布选择](../../lib/features/community/README.md#话题与发布选择)；话题头部、内容分页与选择查询 | `test/features/community/topic_queries_test.dart`、`test/features/community/topic_repository_test.dart`、`test/pages/dynamics/topic_interactions_test.dart` |
| 关注、粉丝与直播关注 | `follow/`、`follow_type/`、`follow_search/`、`follow_tag_sort/`、`live_follow/` | [关注模块](../../lib/features/following/README.md) | `test/pages/follow/`、`test/pages/follow_type/`、`test/pages/live_follow/` |
| 消息、私信、分享 | `msg_feed_top/`、`whisper*`、`share/` | [消息模块](../../lib/services/messaging/README.md)；`msg.dart`、`lib/grpc/im.dart` | `test/services/messaging/` |
| 收藏管理 | `lib/features/favorites/presentation/` | [收藏模块](../../lib/features/favorites/README.md)；账号查询、收藏夹与视频收藏写入 | `test/features/favorites/` |
| 订阅 | `lib/features/subscriptions/presentation/` | [订阅模块](../../lib/features/subscriptions/README.md)；主账号列表、合集详情、取消和失效清理 | `test/features/subscriptions/` |
| 观看历史 | `lib/features/history/presentation/` | [历史模块](../../lib/features/history/README.md)；历史账号角色与游标分页 | `test/features/history/` |
| 稍后再看 | `lib/features/watch_later/presentation/` | [稍后再看模块](../../lib/features/watch_later/README.md)；共享 [内容管理共享实现](../../lib/features/content_library/README.md) | `test/features/watch_later/` |
| 下载与离线 | `lib/features/download/presentation/` | [下载模块](../../lib/features/download/README.md)；`data/`、`domain/`、`application/`；路径在 `lib/app/app_paths.dart` | `test/services/download/`、`test/features/download/`、`test/pages/download/` |
| 设置与主题 | `setting/`、`settings_search/`、`space_setting/` | `lib/common/style.dart`、`lib/utils/theme_utils.dart`、`storage_pref.dart` | `test/pages/setting/`、`test/pages/space_setting/` |
| WebView、DLNA、空降助手 | `webview/`、`dlna/`、`sponsor_block/` | 投屏地址和发现会话归 `features/playback/application/`。其他平台实现从 import 定位。 | `test/pages/webview/`、`test/features/playback/dlna_session_test.dart`、`test/pages/video/cast_results_test.dart`、`test/pages/sponsor_block/`、对应依赖包测试 |

表中的 `models/` 相对 `lib/`；测试及探针路径相对仓库根目录。测试选择、夹具和设备边界见[测试目录](../../test/README.md)，设置生效时机见[设置行为](settings-behavior.md)。

## 首页与内容发现

主壳持有主导航和滚动栏，首页实例持有自己的子 Tab 与刷新意图；子页通过构造回调连接。独立首页和主题预览使用自己的滚动栏，不注册到主壳。`shellBadgesProvider` 调度角标，消息未读快照归账号 Session。外观设置、设置搜索和主壳共用应用作用域的 `badgePreferencesProvider`，保存确认后才通知主壳，作用域释放时关闭广播。搜索词由 `searchHintProvider` 共享并在最后一个订阅释放后销毁。

推荐、热门、排行榜、精选合集、直播发现和 PGC 首页的 Riverpod 调度与共享过滤入口见[内容发现模块](../../lib/features/content_discovery/README.md)。动态作者与分类由[社区模块](../../lib/features/community/README.md)协调，发布与删除通过领域失效信号同步列表。

- `lib/features/content_discovery/presentation/recommendation_viewport.dart` 与卡片共用网格几何，按实际高度、列数和字体缩放补足可视区及一行预取，页脚留白不计入容量。App 推荐按 `idx/pull` 顺序请求；Web 首包按容量取 20～50 项，之后最多并行两页，有序合并并去重。刷新保留历史内容及位置提示。
- `lib/common/widgets/feed_pagination.dart` 以实际滚动范围触发分页；首页首屏补足由推荐 Notifier 负责。连续五页无增长时停止，失败保留内容，刷新、切号或退出使旧查询失效。所有者与快照修订的规则见[状态管理](state-management.md#查询与分页)。
- 内容发现的 `application/blocked_authors.dart` 按主账号同步完整黑名单。同步与首页下载并行，发布前完成过滤；管理页的局部名单不覆盖完整缓存，同步失败沿用该账号缓存，应用内拉黑或解除即时更新。
- 黑名单管理由内容发现的 `application/blacklist.dart` 持有分页和移除操作，与全量过滤共用 `data/blocked_author_repository.dart` 的查询。移除后重读偏移边界页，补齐前移的条目。
- `application/cooperative_authors.dart` 处理合作作者；`rights.is_cooperation`、`is_union_video` 等明确标志触发补查，已知名单直接复用，否则查询详情的 `staff`。请求合并，共用两个并发名额，成功缓存一小时、最多 256 条，失败缓存一分钟；黑名单同步缓存五分钟。
- 首页普通卡片先显示，合作卡片按检查结果局部更新；增删时才更新列表，卡片对象身份保留图片子树。过滤入口在内容发现的 `application/discovery_filter.dart`，领域列表通过 `application/discovery_listing.dart` 统一调度，相关推荐通过 `pages/common/discovery_list_controller.dart` 适配。用户范围见[黑名单屏蔽](../guides/content.md#黑名单屏蔽)。
- `TabActivity`/`TickerMode` 标记活动标签，隐藏页卸载 `CachedImage` 并保留数据和滚动位置。`CachedImageCache` 在动图最后一个监听退出后释放缓存句柄；静态帧沿用 LRU，显式保活句柄可以保留暂停动画。离页后才完成的文件加载，会在首帧完成后回收无人监听的动图。`NetworkImgLayer` 为 B 站质量型缩略图补充卡片尺寸，已有裁剪参数及原图查看/下载沿用原构图或地址。缓存字节不等于全部原生纹理占用，内存与耗时需实测。

## 消息、私信与分享

`lib/services/messaging/` 按主账号 Session 管理未读、通知、会话、聊天和分享；页面通过 Riverpod 订阅或租约使用。修改前核对账号 Session、资源所有者、分页与已读水位，发送待确认时保留草稿并核对历史。入口和释放协议见[消息模块](../../lib/services/messaging/README.md)，回归在 `test/services/messaging/`。

## 播放与窗口

主窗口和启动失败页的自绘标题栏在 `lib/app/desktop_title_bar.dart`，独立播放窗口沿用播放器控件。系统窗口初始化、浮层层级和全屏约束见[桌面窗口与标题栏](architecture.md#桌面窗口与标题栏)，设置生效时机见[桌面窗口设置](settings-behavior.md#桌面窗口)。

页面修改前核对 aid、bvid、cid、`contentKey`、候选来源和起播策略，页面副作用提交时检查资源及 owner 身份。URL 不承担业务内容身份，页面通过 owner 控制播放。约束见[播放状态模型](playback-model.md)，原生交接见[运行流程](runtime-flows.md#播放器切源与网络恢复)。

点播重选入口在 `video/controller.dart`、`video/playback_source.dart`，直播切流在 `live_room/controller.dart`。`lib/features/playback/application/` 持有视频详情查询、视频互动与剧集收藏，以及独立音频的列表快照、排序和双向游标；音频控制与租约交接仍在 `audio/controller.dart`。选择确认、失败重试及迟到回执约定见[状态管理](state-management.md#http-与写入结果)，定向回归见[测试目录](../../test/README.md)。

直播房间的线路查询与首选线路、点赞批次、弹幕互动和屏蔽规则在 `lib/features/playback/application/live_room_*.dart` 与 `live_block_rules.dart`。贡献榜和舰长榜绑定页面、房间及主账号，最后一个订阅离开时释放；未确认的线路切换不覆盖当前线路或偏好。

`lib/services/desktop_playback_windows.dart` 为每个小窗启动独立进程与播放器；主窗口管理排列、声音、设置快照和离线进度。Windows 超分重载、纹理释放与原生验证见[Windows 视频输出](../maintenance/windows-video-output.md)。Android 的 Surface 预挂载、旋转和 MediaCodec 恢复须单独验收。

视频全屏时 `VideoDetailOffstage` 保留面板状态并停止隐藏面板动画及解码。输出限幅只减少表面与纹理开销，源视频仍按原分辨率解码。帧率和资源测量见[维护与排障](../maintenance/troubleshooting.md#复现和测量)。

点播预读策略在 `lib/plugin/pl_player/models/video_buffer_policy.dart`，由 `Pref.initBuffer` 捕获到媒体计划；默认均衡，按时长与字节预算限制前向缓存，后向预算独立保留。Windows 固定 libmpv 支持字节补读阈值，Android 固定库只传时长阈值。跳转沿用原生缓存复用和淘汰，不主动清空；控制器在进度交接后补发当前缓存边界，不能用历史最大值阻止回退。用户设置见[视频缓存](../guides/playback.md#视频缓存)，真实原生验证见[缓存探针](../../tool/probes/README.md#点播缓存与跳转探针)。

## 弹幕合并与调度

点播与直播共用 `danmaku/window_renderer.dart`，分别由 `window_coordinator.dart` 和 `live_queue.dart` 提供候选，挂载为 `view.dart` 与 `live_layer.dart`。媒体时钟、资源归属与来源更新协议见[架构](architecture.md#弹幕显示与来源)。

合并在 `danmaku/merge.dart`，过滤与后台结果接入在 `controller.dart`。在线按分段处理，本地文件稳定排序并保留全文件合并锚点；8～200 字符允许有界编辑差异，数字和否定词保持独立。普通文字池 0/3 参与，自己发送、不同模式、字幕及特殊弹幕独立。匹配最多保留 2048 组、每条检查 64 个候选，后台结果在来源或页面失效后丢弃。功能参考 [PiliNara](https://github.com/Starfallan/PiliNara#改动说明未来计划)，本项目未引入拼音依赖。

帧调度依据所在视图刷新率及播放器实际显示同步状态决定合帧准入。Android 同频目标跟随 vsync，读数容差 0.5 Hz；低档位提前半周期安排唤醒并扣除更新耗时。连续六个稳定且周期匹配的视频间隔允许相位校准，不稳定或显示同步未确认时回到独立调度；设置在播放器初始化时应用，采样到来保留已安排唤醒。模拟刷新和唤醒计数只作调度对照，设备耗电另测。

点播来源就绪仍核对修订，局部失效只撤回对应半开时间区间。弹幕菜单使用播放业务的 `VideoDanmakuInteractions`，操作绑定账号、弹幕及视频；点赞状态查询与重试不提交点赞操作，撤回只在确认成功后更新当前显示。旧渲染器仅作[实验基线](../../tool/experiments/README.md)，用户设置见[播放指南](../guides/playback.md#弹幕合并与帧率)。

## 通用菜单与选择字段

设置项优先使用 `lib/common/widgets/app_select_field.dart`，主题来自 `app_menu_theme.dart`，统一当前值、选中勾和长列表滚动。全局 popup/menu theme 统一菜单表面；内部选项用 `AppPopupMenuItem` 保证悬停圆角及裁剪，普通 `PopupMenuItem` 只继承外层主题。回归在 `test/common/widgets/app_select_field_test.dart`。

## 空降助手

接口适配依据 [BilibiliSponsorBlock 0.17.1](https://github.com/hanydd/BilibiliSponsorBlock/releases/tag/0.17.1) 及其[官方 API](https://github.com/hanydd/BilibiliSponsorBlock/wiki/API)。`skip` 跳过、`mute` 静音，整片标记与精彩时刻只展示；分类按名称保存并兼容旧数组，新增分类保留已有选择。网页 DOM、画中画和灰度分组不属于客户端播放协议。

`lib/features/sponsor_block/` 持有设置快照、持久化和第三方请求。设置页通过 Riverpod 读取确认值；服务器与用户 ID 变化时，旧查询不得覆盖新身份的状态。请求显式不使用 B 站账号，写入不自动重试。

静音通过 owner 独立配置提交，保留用户音量。`test/pages/sponsor_block/block_mixin_test.dart` 与 `test/utils/sponsor_block_settings_test.dart` 验证片段及配置，播放会话测试补充独立音量、配置合并和旧 owner 失效；真实服务和两端声音需设备验证。
