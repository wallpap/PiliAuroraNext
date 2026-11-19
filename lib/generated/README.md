# 协议产物

`bilibili/` 保存 Bilibili protobuf 的既有生成快照。业务适配留在 `lib/grpc/` 和各功能的 `data/`，页面使用功能层接口；架构门禁禁止新增页面直接引用协议产物。静态分析排除此生成目录，仍分析调用方和适配层。

统一行尾后，PiliPlus `a30fcc31043e10cd38c198f47ddd7b23fd6e6163` 与 PiliAurora `767e5f50d604156fab6ad329a062fc873491f50e` 中的 99 个生成文件均与此快照一致。这两份归档都缺少对应 `.proto` 输入、生成命令和生成器锁定版本。更新时先核对源定义、上游修订和发布许可，再固定生成器并运行协议与调用方回归。

PiliPalaX `2da94140c2b49402dac2597aa6553bfc65b8663a` 的 `lib/models/danmaku/dm.proto` 属于较早的协议定义。其 `DmViewReply` 字段 9 是 `string`，当前快照为 `bool`；该定义也缺少当前 `DmSegMobileReq` 的字段 10 和 11。不要用它覆盖现有弹幕协议快照。

从仓库根目录可按用途限定搜索范围。

```powershell
rg -n "keywordBlockingList" lib -g '!lib/generated/**'
rg -n "KeywordBlockingListReply" lib/generated/bilibili
rg -n "VideoController" third_party/media_kit_video/lib
```

准备应用依赖后，在仓库根目录运行 `pwsh -NoProfile -File tool/analyze-protocol.ps1` 可单独分析协议快照。该命令使用应用已解析的依赖和固定 Dart SDK，分析范围仅包含协议文件。

生成文件头的 Dart 语言版本和 `pubspec.lock` 中的 `protobuf` 运行时版本不能用来确定生成器版本。核对新定义时，先比对 `.pbjson.dart` 中的字段编号、类型和 `oneof`，再跑调用方的请求与响应回归。
