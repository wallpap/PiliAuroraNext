# 下载与离线

下载模块使用 Riverpod 管理应用级服务和共享快照，GetX 仅用于兼容现有路由。

| 层 | 入口与职责 |
| --- | --- |
| `domain/` | 下载记录、媒体索引和隔离快照；不依赖 Widget、GetX、网络或存储 |
| `data/` | `download_repository.dart` 管理目录及持久化；`download_api.dart` 解析媒体地址；`download_manager.dart`、响应适配和流写入负责传输 |
| `application/` | `download_service.dart` 编排初始化、创建、暂停、删除和续行；`download_providers.dart` 发布共享状态并核对命令归属 |
| `presentation/` | 下载首页、队列、详情和搜索；页面持有输入、选择、批量操作提示及导航 |

## 所有权与结果

`app/app.dart` 在根 `ProviderScope` 注入仓库、下载客户端、后台提示和播放进度存储。`downloadServiceProvider` 按需创建服务并初始化，应用级保活；页面关闭只释放 Riverpod 订阅，根作用域释放时才关闭传输并保存暂停进度。下载记录属于当前本地目录，不随账号切换清空。

`downloadLibraryProvider` 是所有下载页面的规范状态入口。初始化失败交付错误，不把保留的旧记录当作成功列表。首页分组、详情和搜索均从同一快照派生，详情可独立打开。任务快照复制记录及嵌套媒体信息，`toEntry()` 返回独立副本；页面选择按目录标识保存在 Widget 中，不写回记录。

列表快照与字节进度分开发布，`downloadCurrentTaskProvider` 只更新当前任务行，避免网络进度变化时复制和重建整个离线列表。两个快照 provider 随最后一个页面订阅释放，应用级服务继续保活。

命令同时检查初始化代次与原始记录对象身份。重读目录、删除后重建同 CID 或同路径的记录，均不会接受旧快照的命令。目录重读使旧初始化和准备结果失效；初始化、创建、删除及启动继续共用服务的串行边界。

创建确认落盘后才进入队列；删除确认后才清理播放进度。批量操作串行消费结果，部分失败保留失败项选择；离页或目录失效后停止后续项，已确认删除的进度清理继续完成。批量队列删除期间合并自动续行，避免刚启动的下一项又被删除。

弹幕更新失败保留原文件，较新操作替换旧操作后不接受迟到写回。后台失败由应用入口显示提示，服务不直接操作弹窗。离线播放入口传入当时的播放列表，播放器不再查找下载首页 controller；播放器自身的状态管理与原生资源协议沿用现有实现。

## 验证

```powershell
fvm flutter test --no-pub test/services/download test/features/download test/pages/download test/http/download_response_test.dart test/architecture/dependency_rules_test.dart
fvm flutter analyze --no-pub lib test tool
```

服务测试覆盖真实临时文件、断点续传、持久化和并发归属；provider 测试覆盖共享保活、失败重试、迟到初始化与旧命令；页面测试覆盖详情独立打开、共享列表更新、选择隔离及批量部分成功。依赖门禁禁止领域层导入 UI、应用层导入页面、展示层直连数据层或全局存储。新增 provider 和页面测试及模块静态分析已接入 CI。

实际服务下载、目录权限与文件占用、Android 后台存活，以及 Android/Windows 离线播放和输入交互仍需目标设备验收。构建与测试前提见[构建与测试](../../../doc/development/build-and-test.md)。
