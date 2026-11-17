# 社区模块

动态作者查询与选择位于 `application/`，HTTP 适配位于 `data/`。作者面板按页面实例与主账号对象身份隔离；临时屏蔽与作者选择属于当前主账号的应用会话，账号替换后重置。

`dynamicsAuthorsProvider` 先读取动态作者游标，动态阶段结束后按偏好读取普通关注；重复游标结束动态阶段。MID 去重、资料补齐、已读标记和稳定未读排序由同一查询持有。失败保留原游标，连续五页无增长暂停自动补读并交付继续入口；刷新、换凭据及最后订阅释放废弃旧结果。

`DynamicsPage` 与 `UpPanel` 持有 Tab、滚动及直播展开状态。主壳仅接受 Widget 注册的滚动/刷新句柄；注册按对象身份释放。分类页通过构造回调注册，父页刷新等待作者和当前分类两个 Future，不通过业务 controller 反查。

回归：`fvm flutter test --no-pub test/pages/dynamics/overview_results_test.dart test/pages/dynamics/management_results_test.dart test/architecture/dependency_rules_test.dart`。真实服务与 Android/Windows 交互另行设备验收。
