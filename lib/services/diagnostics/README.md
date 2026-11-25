# 诊断与轻量内存归属

## 应用与播放日志

`runtime.jsonl` 与 `player.jsonl` 每行保存一个 `schema=1` 的 `DiagnosticLogRecord`。采集、读取历史和窗口转发共用事件模型，旧文件仍可读取。事件有 `channel`、`level`、`category` 和 `message`，需要时添加 `details` 或 `stack`。导出会清洗消息内容，字符串、列表和对象仍各自保持原有类型。

按 `time` 对照不同来源的事件。同一进程内用 `elapsedUs` 计算间隔；定位窗口转发副本时用 `(runId, processId, windowId, sequence)`。

查播放问题先按 `details.playerId` 和 `details.mediaGeneration` 分组。`decoder.state.changed` 只在首次观测或解码器状态变化时写入。周期性的 `playback.snapshot` 只在播放日志设为“跟踪”、性能记录关闭时写入。故障快照见 `details.state`。`mpv.error.context` 按 mpv 的 `prefix` 限频，`details.mpvErrorSequence` 指向同一来源的原始 mpv 日志。

诊断页最多显示应用和播放日志各 200 条，可按消息、类别或路由搜索，再按通道和等级缩小范围。展开记录就能查看来源、详情和堆栈。筛选只影响页面列表，导出仍使用日志文件快照。

### 导出与脱敏

导出先复制本地文件，再由后台 isolate 对副本脱敏、去重和压缩。主文件已有子窗口转发的同一事件时，ZIP 保留主文件中的副本。子窗口独有的记录仍会导出；来源字段不全时不会按消息文本猜测重复。`manifest.json` 的 `export.duplicateRecords` 是移除的镜像数，`export.skippedRecords` 是无法解析而跳过的记录数。清单版本与事件版本各自维护。

复制单条日志与导出诊断包共用脱敏规则，本地原始日志保持不变。网络地址保留主机、端口和路径，删除用户信息和片段，整个查询串换成占位符。凭据字段、跨行认证头、私钥和本地文件 URL 也会替换；JSON 文本中的凭据按完整值处理。路径或消息仍可能含个人信息，分享前请检查。用户操作见[分享诊断记录](../../../doc/guides/data-security.md#分享诊断记录)。

## 性能采集与内存归属

在“设置 → 日志与诊断 → 记录性能”开启采集，建议每秒采样。退出播放后继续记录约 90 秒再导出。多窗口协调和文件轮转沿用现有流程，无需脚本或管理员权限。

## 采集与所有权

`diagnostics.dart` 将已有性能 sample 交给 `MemoryAttribution.observe`，每 5 秒记录一次归属快照，观测到阶段变化时追加记录；不增加平台轮询、GPU 同步或强制回收。

`memory_attribution.dart` 按 player 源和 runtimeId 识别播放、全屏、路由及离页。离页对照取首次达到 5/30/90 秒的正常采样，`afterCloseElapsedMs` 保留实际时间。短于采样间隔的操作可能遗漏。

原生 `native_memory_stats.h` 在创建、释放、加载交接及 Flutter 注销回执处更新账本。每个存活输出有匿名 ownerId，runtimeId/loadId 表示当前绑定，资源可能早于此次 load 创建。析构删除输出明细，created/released 全局计数继续累计。

纹理登记数覆盖插件注册到注销回执；引擎导入的 D3D 对象可能继续存活。`ownerStatus=unsupported` 表示插件缺少输出明细。图像缓存、Image/Picture、插件输出、raster/IO 沿用各自口径，名义字节、Private、WC 和 GPU 统计可能重叠，不能相加为独占总量。

日常采集关闭调用栈和图形资源详情。专用引擎支持时，构建参数 `PILIAURORANEXT_GRAPHICS_DETAILS=true` 请求详情，`PILIAURORANEXT_GRAPHICS_STACKS=true` 开启句柄创建栈。普通引擎返回 unsupported；交换链、引擎实际导入、解码器与驱动内部、Dart 堆列为 unobserved。详见[Windows 图形诊断引擎](../../../tool/engine/windows_memory/README.md)。

## 数据协议与上限

`performance.jsonl` 的 `type=memoryAttribution`、`schema=1` 记录复用 sample 的 runId、processId、windowId、session，sequence 独立递增。`collectionUs` 仅统计归属计算，不含平台读取、脱敏、编码及写盘。

| 记录 | 内容与异常语义 |
| --- | --- |
| `kind=snapshot` | 进程页、缓存年龄和 owners；页扫描不完整时 WC/RW 为 null |
| `kind=stage` | 阶段、播放编号、基线、峰值及 Private/WC 差值；首条观测已在播放时无基线，新播放或并发介入标记 interveningPlayback |

源读取失败不生成离页事件。账本只保存计数和值，不持有播放器、图片或原生资源。

| 容量 | 溢出标记 |
| --- | --- |
| 8 个活动播放、8 个待退出对照 | omittedActivePlayers/omittedFollowUps |
| 8 个原生存活输出明细 | omittedOwners；全局总计继续累计 |
| 导出 32 组、每组最新 64 条阶段 | 摘要保留溢出、损坏及未知状态 |

导出在后台 isolate 流式读取本次导出的历史文件，按 runId＋PID＋session＋windowId 生成 `memory-summary.json`，兼容轮转文件乱序。停止或重启后仍可生成；没有归属记录时返回 notRecorded。复制与脱敏沿用原协议，资源字典和每个输出分别限界。

## 验证

```powershell
fvm flutter test --no-pub test/services/diagnostics/ test/services/desktop_diagnostics_test.dart test/pages/about/diagnostics_page_test.dart
python -m unittest tool/probes/windows/native_memory_stats_test.py
python tool/probes/windows/windows_renderer_release_probe.py
```

`tool/experiments/diagnostics/memory_attribution_benchmark.dart` 回放一个或多个解压目录，统计归属计算耗时与载荷：

```powershell
fvm dart run tool/experiments/diagnostics/memory_attribution_benchmark.dart <解压目录>
```

离线回放和原生账本并发测试仅验证局部行为。真实设备需对照采集开关前后的 CPU、帧时间、内存与写盘量。
