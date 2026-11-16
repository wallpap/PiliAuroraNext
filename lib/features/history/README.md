# 观看历史

`historyFeedProvider` 是分类与搜索的状态入口，`HistoryLibrary` 是删除、清空和暂停/恢复的写入 Interface；远端与缓存 Adapter 在 `data/`，数据类型在 `domain/`，输入、选择、Tab、滚动和弹窗在 `presentation/`。

账号使用 `historyAccountProvider`：已登录的心跳账号优先，否则回退主账号。账号切换、凭据替换、删除和重载通过 `Accounts.historyChanges` 通知；按对象身份重建查询，不能用 UID 相等代替凭据归属。

普通列表使用 `(oid, viewAt)` 游标，搜索使用已提交关键词和页码。列表按 `(business, kid)` 去重，游标重复停止；失败保留内容和游标，显式重试；刷新、账号替换和释放后的迟到结果不回写。分类元信息在分页时保留，不与旧账号混用。

删除、清空与暂停写入共用账号锁；只有确认成功才使所有分类与搜索失效。页面选择独立于记录对象，待确认和失败保留选择与原查询，成功重读列表。暂停状态由确认回执发布，旧查询不覆盖新状态；缓存写入串行，失败沿调用方交付，已确认的远端值保留。启动与登录同步通过 `HistoryLibrary.legacy.status` 使用同一查询代次，保留等待落盘与原始缓存错误的 Future 语义。

```powershell
fvm flutter test --no-pub test/features/history test/utils/history_status_lifecycle_test.dart test/utils/background_sync_results_test.dart test/utils/accounts test/architecture/dependency_rules_test.dart
fvm flutter analyze --no-pub lib test tool
```

真实历史分页、暂停后的服务端记录行为与 Android/Windows 输入仍需目标设备验收。
