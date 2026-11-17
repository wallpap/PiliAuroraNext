# 社区模块

动态作者查询与选择位于 `application/`，HTTP 适配位于 `data/`。作者面板按页面实例与主账号对象身份隔离；临时屏蔽与作者选择属于当前主账号的应用会话，账号替换后重置。

`dynamicsAuthorsProvider` 先读取动态作者游标，动态阶段结束后按偏好读取普通关注；重复游标结束动态阶段。MID 去重、资料补齐、已读标记和稳定未读排序由同一查询持有。失败保留原游标，连续五页无增长暂停自动补读并交付继续入口；刷新、换凭据及最后订阅释放废弃旧结果。

`DynamicsPage` 与 `UpPanel` 持有 Tab、滚动及直播展开状态。主壳仅接受 Widget 注册的滚动/刷新句柄；注册按对象身份释放。分类页通过构造回调注册，父页刷新等待作者和当前分类两个 Future，不通过业务 controller 反查。

回归：`fvm flutter test --no-pub test/pages/dynamics/overview_results_test.dart test/pages/dynamics/management_results_test.dart test/architecture/dependency_rules_test.dart`。真实服务与 Android/Windows 交互另行设备验收。

`dynamicsFeedProvider` 按页面、类型与作者绑定主账号，复用 `DiscoveryListing` 的所有者和五页补读预算。HTTP Adapter 每次只读取一页；失败不推进游标，重复游标结束分页。删除按动态 ID 互斥，成功事件同步所有已订阅分类，并排除在途页内相同 ID；分页期间仍可删除。发布与转发通过 `DynamicsUpdates` 废弃当前查询，不再从工具层查找或插入页面 controller。临时屏蔽按会话快照重建列表，展开只修改当前快照内的折叠 ID。

`test/features/community/dynamics_feed_test.dart` 覆盖账号、分页、删除、发布、展开和页面释放，已接入 CI；分类页滚动与父页刷新只通过构造回调协调。

小站由 `bubbleFeedProvider` 按页面、小站、分类与排序持有主账号查询。路由显式传入小站 ID，子分类沿同一资源和排序创建查询，不读取隐式路由参数。目录和列表同轮发布，续页保留目录；目录替换销毁旧 Tab 子树。Widget 持有滚动，实际视口触发分页；失败保留原页码并可重试。`test/pages/bubble/controller_test.dart` 覆盖同 UID 换凭据、排序乱序、失败重试、双小站和活动 Tab 释放。
