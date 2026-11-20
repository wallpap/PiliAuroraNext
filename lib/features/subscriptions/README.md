# 订阅管理

订阅列表、合集详情、取消与失效清理共用主账号和本地隐藏记录。

## 目录与约束

- `domain/`：订阅、合集视频、分页响应和清理结果。
- `data/`：显式传入账号的 HTTP Adapter 与按账号、订阅类型及 ID 隔离的隐藏记录。
- `application/subscription_cleanup.dart`：完整快照扫描、视频有效性判断、待确认取消与有限分页；不处理弹窗和提示。
- `application/subscription_library.dart`：Riverpod 查询、写入锁、清理进度、账号归属与成功失效信号；复用[共享分页实现](../content_library/README.md)。
- `presentation/`：列表与合集详情、滚动控制器、路由参数、确认弹窗和结果提示。GetX 只用于路由兼容。

## 所有权与异步结果

根 `ProviderScope` 持有 `subscriptionLibraryProvider`，容器释放时关闭失效事件流。页面通过 `SubscriptionQuery(owner: 页面实例, id: 合集 ID 或 null)` 获取独立 autoDispose 查询，退出后释放账号与失效订阅。主账号按对象身份隔离，同 UID 更换凭据也会重建查询；旧结果不更新新账号，不读取新账号的隐藏记录，也不继续补页。

查询快照的列表容器不可变，分页按订阅类型与 ID 或视频 ID 去重。下一页由过滤前的远端响应计算；刷新和成功写入替换来源身份，旧分页与旧弹窗失效。分页失败保留已有内容和游标，等待显式重试。连续隐藏页最多自动读取五页，之后保留游标并暂停自动请求，页面提供继续加载入口。

`subscriptionOperationsProvider` 发布当前账号的写入占位和清理进度。取消与清理共用 `SubscriptionLibrary` 的账号写入锁；清理还绑定发起页面是否存活。换凭据、释放页面或操作 provider 后，旧扫描不再发起后续读取和写入。已经发送的取消仍处理所属账号的确认结果；提示和关闭弹窗另检查当前页面、路由与账号。

取消明确成功时使当前账号的订阅列表和合集查询统一失效；失败或待确认保留原快照及弹窗。清理完成后统一刷新，包括存在待确认取消的情况，提示用户核对服务端状态。业务层返回结果，页面负责展示。

清理先读全量订阅快照再写入，避免取消后分页前移漏项。只有全部内容确认失效才取消；请求失败、分页不完整和结果待确认分别保留语义。远端取消成功后的本地记录清理失败不改变远端成功结论。

## 验证

```powershell
fvm flutter test --no-pub test/features/subscriptions test/architecture/dependency_rules_test.dart
```

`subscription_library_test.dart` 验证查询身份、账号更换、释放、分页、隐藏页预算、互斥与跨页面失效，并检查实际页面的标题更新。`operation_results_test.dart` 使用受控 HTTP 响应验证取消弹窗、待确认、缓存失败和清理后的实际刷新；`cleanup_test.dart` 与 `hidden_media_test.dart` 分别覆盖扫描算法和 Hive 隔离。依赖规则检查四层方向。

这些测试使用模拟数据。真实账号下的取消、全量扫描、封面 Hero 动画及 Android/Windows 布局仍需设备验收。
