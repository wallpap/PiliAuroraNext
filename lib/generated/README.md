# 协议产物

`bilibili/` 保存 Bilibili protobuf 的既有生成快照。业务适配留在 `lib/grpc/` 和各功能的 `data/`，页面使用功能层接口；架构门禁禁止新增页面直接引用协议产物。静态分析排除此生成目录，仍分析调用方和适配层。

当前分支未保存对应 `.proto` 输入、生成命令或生成器锁定版本。保持快照内容原样；后续更新需先确认上游修订与发布许可，固定源定义和生成器版本，再从源生成并核对差异、运行协议与调用方回归。

从仓库根目录可按用途限定搜索范围。

```powershell
rg -n "keywordBlockingList" lib -g '!lib/generated/**'
rg -n "KeywordBlockingListReply" lib/generated/bilibili
rg -n "VideoController" third_party/media_kit_video/lib
```

生成文件头的 Dart 语言版本和 `pubspec.lock` 中的 `protobuf` 运行时版本不能用来确定生成器版本。核对新定义时，先比对 `.pbjson.dart` 中的字段编号、类型和 `oneof`，再跑调用方的请求与响应回归。
