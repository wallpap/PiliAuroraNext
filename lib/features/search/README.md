# 搜索

`application/search_home.dart` 持有联想、热搜、推荐和历史。页面持有输入、焦点及导航；编辑输入立即使旧联想失效，防抖只延后新请求。`data/search_local_store.dart` 保留既有 Hive 键和历史格式。

首页壳通过 `application/search_hint.dart` 消费默认搜索词。关闭偏好立即清空展示并撤销在途结果，离开首页释放偏好订阅。

`application/search_results.dart` 按页面实例、已提交关键词和筛选隔离查询；推荐账号决定凭据，主账号决定屏蔽规则。`application/scoped_search.dart` 按同一原则分别从主账号读取空间、从推荐账号读取直播。数据层适配 HTTP/gRPC，空间投稿卡片不消费生成协议。验证由应用层固定账号并校验查询归属，展示层打开原验证窗口并交付提示。

回归入口为 `test/pages/search/`、`test/pages/search_results/`、`test/pages/scoped_search/`、`test/http/search_response_test.dart` 和 `test/utils/gaia_validation_test.dart`。真实验证码与服务交互需目标设备验证。
