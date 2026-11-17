# 内容管理共享实现

此目录集中稍后再看、历史、收藏和订阅实际重复的行为。各领域保留自己的查询与写入 Interface，不建立通用业务 controller。

- `application/paged_feed.dart`：不可变列表容器、来源身份、账号归属、串行分页、去重、空页预算和显式重试；领域给出下一游标，失败不推进。
- `application/library_module.dart`：按账号对象身份互斥写入，保留原始失败和待确认语义，成功发布失效事件；不缓存列表。
- `application/library_preferences.dart` 与 `data/`：连续播放偏好读取、订阅和确认保存。
- `presentation/`：根据实际滚动范围分页，并让确认弹窗持有提交锁和错误信息。

`FeedState.source` 是一次有效查询的身份，分页保留它，刷新或切号替换它。延迟确认须同时核对来源和账号；结果展示另核对页面与账号，不能因成功写入引发查询失效就误判写入失败。

空页预算默认结束查询。订阅设置 `endOnEmptyBudget = false`，预算耗尽时保留游标并通过 `FeedState.error` 暂停自动分页；显式 `loadMore(retry: true)` 才继续，避免连续隐藏内容触发无限请求。

测试通过各领域 provider 和写入 Interface 验证这些行为；不为共享 Implementation 叠加一套镜像测试。领域源码入口见[功能地图](../../../doc/development/features.md)。
