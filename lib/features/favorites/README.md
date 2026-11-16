# 收藏管理

`favoriteFeedProvider` 交付收藏夹、详情/搜索、追番分组、专栏、笔记、话题和课堂查询；`FavoriteLibrary` 提供账号锁、收藏夹管理与视频收藏写入 Interface。HTTP 和本地隐藏记录通过 `data/` Adapter 接入，领域模型位于 `domain/`，输入、选择、排序草稿、导航和弹窗由 `presentation/` 持有。

查询按页面身份、已提交筛选和主账号对象身份隔离。同 UID 换凭据仍重建查询；刷新、切号和释放后丢弃迟到结果。分页按领域 ID 去重，失败保留游标并显式重试；首屏隐藏后为空时沿原始游标有限补位。详情保留服务端所有者和数量，支持正/倒序分页；倒序预查询失效后停止后续请求。追番按原始条目累计到总数，不假定服务端页大小。

删除、清空失效内容、新建/编辑/删除收藏夹、收藏夹订阅、排序、复制/移动及视频收藏共用按账号身份的写入锁。确认成功统一失效当前账号下的各类查询，从新分页边界重读，避免删除或移动后的偏移遗漏；失败和待确认不修改确认快照。页面的选择和排序草稿独立于模型，不通过共享对象修改计数。

视频收藏面板使用 `favoriteMembershipProvider` 查询确认归属，页面只保存勾选差量；创建收藏夹后合并原草稿并勾选新夹。提交须核对账号、目标和查询修订，只有确认成功才回调播放器。播放器/音频通过固定目标、来源归属判断和确认回调接入；快速收藏将查询、目标检查和写入放在同一个账号锁中。文章、话题、追番、三连和稍后再看转入收藏的旧入口通过同一写入 Interface 发布成功失效，不持有第二份收藏列表。

连续播放偏好复用 `content_library` 的 `playAllProvider`，保存确认后才发布，与稍后再看保持一致。排序保留页面自己的草稿，收藏夹首项保持固定；详情排序按服务端相邻资源协议提交，后续页加入草稿前核对来源和已加载前缀。

```powershell
fvm flutter test --no-pub test/features/favorites test/features/watch_later test/features/history test/http/fav_response_test.dart test/pages/article/controller_results_test.dart test/pages/pgc/follow_results_test.dart test/architecture/dependency_rules_test.dart
fvm flutter analyze --no-pub lib test tool
```

真实服务上的数量、排序/复制/移动结果、封面选取与裁剪，以及 Android/Windows 的完整交互仍需目标设备验收。
