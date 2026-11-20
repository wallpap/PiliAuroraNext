# 稍后再看

`application/later_library.dart` 是跨入口写入的 Interface，`laterFeedProvider` 是列表和搜索的状态入口。`data/later_repository.dart` 是远端协议 Adapter，`domain/` 保存数据类型，`presentation/` 持有输入、排序、选择、滚动和弹窗。路由直接进入展示层。

查询按页面 owner、分类、已提交关键词、排序和主账号对象身份隔离；同 UID 换凭据也重建查询。列表不写 `checked`，不同页面的选择相互独立。分页串行、按 aid 去重，失败保留内容和游标，显式重试；刷新和释放丢弃迟到分页。

添加、移除、清空和复制/移动共用账号写锁。只有确认成功才发布失效信号，使各标签、数量和搜索重新查询；拒绝或待确认保留选择与原查询。确认前核对来源，确认后只关闭所属弹窗。连续播放偏好通过共享设置入口确认落盘后发布。

播放器和卡片菜单通过 `LaterLibrary.legacy` 使用同一个 Module；它仅持有写锁与失效事件，不保存第二份列表。新页面通过 provider 注入，测试替换远端 Adapter。播放器自身的状态与原生资源协议保持原有所有权。

验证入口：

```powershell
fvm flutter test --no-pub test/features/watch_later test/features/favorites/operation_results_test.dart test/pages/video/media_navigation_test.dart test/architecture/dependency_rules_test.dart
fvm flutter analyze --no-pub lib test tool
```

真实服务分页、复制/移动、连续播放和 Android/Windows 输入交互仍需设备验收。
