# 关注与分组

`application/` 持有关注列表、粉丝与共同关注、直播关注、分组及排序。查询固定主账号，换账号或同 UID 换凭据后丢弃旧响应。分组写入按 UID 互斥，同一凭据下刷新等本次写入完成后再读取目录；换凭据不等待旧目录。分页失败保留已确认列表并重试原页。

`data/following_repository.dart` 绑定请求参数、关注分组模型及排序存储。`presentation/follow_actions_dialog.dart` 继续提供关注、特别关注、设置分组和取消关注入口。Widget 保持选项草稿、导航和提示，分组保存仍以领域确认结果为准。

回归入口为 `test/pages/follow/`、`test/pages/follow_type/`、`test/pages/live_follow/`，覆盖分页、刷新与写入竞争、换凭据及原路由。
