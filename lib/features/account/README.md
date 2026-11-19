# 账号共享资料与个人中心

登录资格来自 `Accounts` 的角色对象，Riverpod 订阅角色变化；资料缓存只提供展示数据。共享资料、个人中心、登录同步与资料编辑通过同一模块发布确认快照。

## 入口与职责

- `domain/`：用户资料、等级与统计模型，保留既有 Hive typeId 和字段编号。
- `data/profile_repository.dart`：显式账号的资料与统计请求、按 UID 隔离的 Hive 资料缓存。
- `application/account_profile.dart`：资料发布顺序、查询代次、缓存串行写入，以及共享资料和统计 provider。登录同步与资料编辑共用 `AccountProfile.legacy`，不创建额外 ProviderContainer。
- `application/account_preferences.dart`：从心跳角色派生无痕状态，观察主题偏好。账号身份与角色持久化仍由 `utils/accounts.dart` 持有，Riverpod 桥接入口为 `services/account_providers.dart`。
- `application/profile_editor.dart` 与 `data/profile_editor_repository.dart`：编辑实例的资料查询、写入和待确认核对；页面持有文本、图片选择和弹窗。
- `application/account_roles.dart` 与 `presentation/account_switch_dialog.dart`：账号切换草稿只保存 UID，确认时解析最新凭据。角色已改动时拒绝旧草稿。
- `application/login_session.dart`：登录请求编排、App 与 Cookie 凭据保存。登录表单持有输入和验证码显示，编辑或关闭时忽略过期确认。
- `application/account_logout.dart` 与 `application/login_devices.dart`：退出登录、仅清理本地以及登录设备查询。退出回执按凭据身份归属，避免清理同 UID 的新登录。
- `presentation/`：个人中心、收藏摘要与无痕交互；个人中心复用收藏领域的查询和成功失效通知。原 `pages/mine/view.dart` 仅适配旧壳的滚动、消息按钮和切号对话框，通过参数交给展示层。

## 所有权与结果

主账号按对象身份隔离，同 UID 更换凭据也会使旧请求失效。共享资料与统计为 autoDispose provider；资料刷新检查账号、查询代次和观察者存活，统计由 Riverpod 隔离异步结果。旧未登录响应不能注销新账号。

登录查询被同账号页面刷新淘汰时，仍交付确认登录成功，供 `LoginUtils` 完成网页 Cookie 与历史状态同步；旧资料不再覆盖较新快照。换凭据后则不交付。原生 Cookie 同步继续使用既有串行队列，后台失败单独记录。

已确认的改名和头像会创建新展示快照，立即通知其他入口并淘汰早先查询；本地保存失败单独交付，不把远端成功改为失败。资料写入按顺序执行，防止同 UID 的旧写入覆盖新凭据确认的资料。缓存使用 `userInfoCache:<mid>`，只在 UID 匹配时兼容读取旧 `userInfoCache`，匿名账号不读取缓存。

临时无痕只替换运行时心跳角色，立即通知历史账号查询；保存为永久时维护原心跳账号的角色标记，退出时恢复主账号。临时期间更换凭据也更新待持久化的角色所有者。主题以 Hive 已保存值为准，设置页和个人中心共享观察结果。

## 验证与范围

```powershell
fvm flutter test --no-pub test/features/account test/services/account_providers_test.dart test/utils/account_profile_lifecycle_test.dart test/utils/background_sync_results_test.dart test/pages/member_profile test/architecture/dependency_rules_test.dart
```

回归覆盖资料隔离、同 UID 新凭据、释放与刷新竞争、登录同步交付、缓存失败及串行写入、真实角色通知、无痕持久化、主题观察，以及实际个人中心的资料编辑和切号展示。架构测试检查四层依赖并禁止恢复旧入口。

凭证继续沿用既有存储格式。真实 Cookie、远端登录、Android/Windows 原生交互和完整应用构建需另行验收。
