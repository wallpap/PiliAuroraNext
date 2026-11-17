# 内容发现模块

首页推荐的查询调度和展示由本模块持有。入口 `pages/rcmd/view.dart` 只适配旧首页壳的滚动与刷新注册；热门由页面实例 family 的 `hotFeedProvider` 持有，Widget 只持有滚动句柄。动态等历史列表通过 `DiscoveryListController` 复用作者过滤，业务状态继续由各自页面持有。

## 状态与依赖

- `application/recommendation_feed.dart`：autoDispose `recommendationFeedProvider` 持有推荐列表、查询代次、并发下载、补位、历史位置、重试与移除。查询同时绑定主账号屏蔽规则和推荐账号对象身份；同 UID 换凭据也淘汰旧查询。共用凭据的两条角色通知同步撤销旧查询，在微任务中合并重读。
- `data/recommendation_repository.dart`：接收查询捕获的推荐账号、App/Web 来源、页索引、容量和取消令牌，适配 `VideoHttp`。请求排队后不再读取当前推荐角色。
- `application/discovery_filter.dart`：新推荐与历史发现列表共用过滤、去重和待补查作者判定。黑名单同步仍由 `BlockedAuthors` 持有，合作作者身份缓存与两路检查由 `CooperativeAuthors.shared` 持有；屏蔽结论每次按当前规则重算。
- `application/recommendation_preferences.dart`：观察 Hive 的 App/Web、保留上次内容与历史提示开关。来源切换取消旧查询并从第一页重读；历史开关更新当前提示与下一次刷新，不要求设置页找到已挂载的推荐页。
- `presentation/`：Widget 持有滚动控制器和保活；视口仅上报容量、列数与活动状态。`RecommendationPageHandle` 供旧首页壳刷新、滚动和诊断读取；卸载按句柄身份注销，旧页面不能移除新页面注册。

没有独立领域对象时直接沿用共享的视频模型；不为目录对称增加转发模型。列表快照不可修改，合作作者集合沿共享模型保留原有补查语义。

## 调度约束

首次布局后开始请求，按实际网格补满视口及一行预取，页脚不计入容量。App 顺序推进 `idx/pull`；Web 首包取 20～50 项，之后最多两页并发，按索引有序发布、按内容 ID 去重。黑名单同步与下载并行，发布等待同步完成；下载不等待合作作者补查。

合作视频先保留对应位置的骨架，再逐张揭示。`recommendationCardPendingProvider` 按卡片订阅；只揭示卡片时不发布新列表或重建普通卡片。被过滤后沿原查询补位，连续五页无有效增长停止。分页失败保留内容与页索引，由用户重试原页。

刷新保留同一账号/来源下已完成检查的历史项，超过 200 项时保留前 50 项。首包等待或失败期间保留历史提示的相对位置；来源或任一账号角色变化时隐藏旧列表及提示。后台标签保留数据和滚动，完成在途响应后不继续调度；后台换号立即清空旧数据，返回时按保留的视口重读。

页面最后一个订阅释放时取消下载、结束诊断并释放账号/偏好订阅；旧下载、过滤准备和合作作者结果均不能写回替换后的查询。Provider 重建也重新建立查询归属。

## 验证

```powershell
fvm flutter test --no-pub test/features/content_discovery/ test/pages/common/discovery_list_controller_test.dart test/pages/common/discovery_account_results_test.dart test/pages/home/controller_lifecycle_test.dart test/architecture/dependency_rules_test.dart
```

测试覆盖模拟时序、真实角色通知与 Hive 偏好、页面释放、历史位置、有序并发和卡片子树保留；均纳入 `tool/run-ci-tests.ps1`。HTTP 显式账号与签名等待回归见 `test/http/video_query_results_test.dart`。封面下载/解码由图片模块独立验证；真实推荐服务、Android/Windows 滚动与探针性能仍需设备验收。

## 发现列表迁移

`application/discovery_listing.dart` 统一负责主账号屏蔽与推荐账号身份、查询代次、分页互斥、合作作者检查、过滤补读和页尾重试。刷新与任一账号对象替换立即隐藏旧内容；失败保留已完成列表和原页码。连续五页无增长后暂停自动读取，用户可显式继续。总数按过滤前条目累计，页面移除不改变远端游标。旧响应不提交列表或元数据。

热门通过 `data/hot_repository.dart` 固定请求账号，首页壳仅持有 Widget 注册的滚动／刷新句柄；卸载按句柄身份注销。共享回归位于 `test/features/content_discovery/discovery_listing_test.dart`，已接入 CI。

排行榜由 `rankFeedProvider` 按页面实例和分类隔离，UGC／番剧／影视三个 Adapter 路径均使用查询捕获的推荐账号。榜单为单次快照，禁止自动分页；分类 Tab、滚动与重复点击回顶由 Widget 持有，子页通过窄句柄注册，不再互找控制器。真实 HTTP 换凭据与双页面回归见 `rank_feed_test.dart`。
