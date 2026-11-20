# 协议产物

`bilibili/` 保存 Bilibili protobuf 的 Dart 产物。消息定义位于 [`tool/protocol/schema/`](../../tool/protocol/schema/)，传输适配位于 `lib/grpc/` 和功能的数据层。页面使用功能接口。应用分析覆盖适配和调用方，协议产物单独分析。

33 份 `.proto` 从 `18674549` 的 Dart 基线恢复，沿用该基线的来源和许可。基线与 PiliPlus `a30fcc31043e10cd38c198f47ddd7b23fd6e6163`、PiliAurora `767e5f50d604156fab6ad329a062fc873491f50e` 的生成快照一致。恢复使用嵌入的消息和枚举描述符、Dart 的包与导入信息以及可见的文档注释。该输入记录客户端已有的协议视图，历史文件级选项及 RPC 服务声明没有保存在快照中。RPC 路径继续由 `lib/grpc/` 维护。

恢复校验比对了全部 99 个文件。统一行尾后 90 个逐字一致，其余只有私有导入别名或排版差异。33 个反射描述文件均完全一致。

PiliPalaX `2da94140c2b49402dac2597aa6553bfc65b8663a` 的 `lib/models/danmaku/dm.proto` 属于较早的协议定义。其 `DmViewReply` 字段 9 是 `string`，当前快照为 `bool`；该定义也缺少当前 `DmSegMobileReq` 的字段 10 和 11。不要用它覆盖现有弹幕协议快照。

## 生成与检查

Windows x64 和 Linux x64 使用 FVM 固定 Dart SDK、脚本固定的 `protoc` 发布包及 SHA-256、独立锁文件固定的 `protoc_plugin`。工具依赖在 `build/` 临时目录解析。默认检查产物，更新协议时加 `-Write`，审查消息字段和调用方变化，再提交定义、生成产物和对应适配。

```powershell
pwsh -NoProfile -File tool/generate-protocol.ps1
pwsh -NoProfile -File tool/analyze-protocol.ps1
```

分析命令需要先解析应用依赖。CI 验证可复现性并单独分析生成目录。

## 源码检索

根目录 `.ignore` 让遵循 ripgrep 忽略规则的编辑器和 `rg` 默认聚焦业务代码。以下命令分别检索业务、协议定义和定制依赖。

```powershell
rg -n "keywordBlockingList" lib
rg --no-ignore-dot -n "message KeywordBlockingListReply" tool/protocol/schema
rg --no-ignore-dot -n "VideoController" third_party/media_kit_video/lib
```
