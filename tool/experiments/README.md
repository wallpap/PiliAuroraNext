# 按需实验

当前采用的修复、引擎和默认预算见[默认构建与策略](../../doc/development/build-defaults.md)。应用构建走[普通入口](../../doc/development/build-and-test.md#构建)，本目录保留可复用的对照工具。

## 实验资料归档

从[默认构建与策略](../../doc/development/build-defaults.md)核对当前采用项，从[历史排障经验](../../doc/diagnostic-notes/README.md)查找可复用的方法。单次调查记录保留在本地 `doc/dev/diagnostics/`，摘要注明适用的构建、设备、输入和测量条件。

可再生的编译产物、采集输出和逐次明细保存在 `build/`。需要长期留存的历史证据按采集日期打包至本地 `doc/dev/diagnostics/archives/`。清单记录归档名、原相对路径、字节数和 SHA-256。核对归档成员的校验值后，再整体或按需解包到 `build/`。可清理的工作副本和归档分开存放。项目默认搜索忽略本地诊断资料，需要查旧结论时可用 `rg --no-ignore -n -g '*.md' '<关键词>' doc/dev/diagnostics`。

复核时用报告记录的版本、设备和测量条件重现实验。保留影响结论的失败结果和后来更正。旧报告引用的归档文件可凭原路径在清单中定位。

## 运行实验

在仓库根目录通过 FVM 运行，使用与正式测试相同的项目依赖：

```powershell
fvm flutter test tool/experiments/
```

此目录不进入默认 `fvm flutter test` 的 `test/` 扫描。可将单个文件路径传给命令，独立运行对应实验。

离线分析器的逻辑回归可并行执行：`uv run --locked python tool/run_python_tests.py --suite android-analysis --suite danmaku-analysis --jobs 2`。该命令不运行设备实验或性能测量。

| 文件 | 内容 |
| --- | --- |
| `images/decode_work_test.dart` | 从本地文件读取同一张 PNG，对照单请求和四次并发请求，再分别播放 GIF、WebP 各四轮。使用真实 decoder，测试时钟跳过帧间等待。每项预热两次，输出七次测量的耗时中位数和原生取帧数。 |
| `danmaku/raster_cache_capacity_test.dart` | 对照 16/24/32 MiB 缓存容量在唯一内容、重复内容和预热扫描中的命中、光栅化与淘汰；检查预算和预期命中关系。 |
| `danmaku/file_order_reuse_test.dart` | 用真实 protobuf 临时文件对照每次范围重建外部排序、来源排序产物冷构建和复用读取；核对相同范围内容、稳定次序、解码扫描量、产物复用及清理，输出宿主 CPU/磁盘耗时。 |
| `danmaku/cpu_hotpaths_benchmark_test.dart` | 对照密集候选筛选、来源缓存保留和两类近似文本合并的耗时、输出校验值及进程峰值 RSS。 |
| `danmaku/density_metrics.dart`、`density_metrics_test.dart` | 共享视口裁剪、逐权重显示及拥挤统计，验证不可见项、曝光积分、相对Top-N对照。 |
| `danmaku/retention_budget_test.dart` | 完整真实分段及六分钟合成流，对照16/20/24MiB、30000/36000/42000条来源额度。 |
| `danmaku/relative_density_analysis.py` | 将多组聚合报告汇总为逐权重CSV、JSON及Markdown，保留各配置实际覆盖的范围数。 |
| `danmaku/priority_density_test.dart` | 使用可选真实弹幕和密集合成素材，统计权重、密度、轨道准入和高权重保留；测量布局耗时，字宽为估算值。 |
| `danmaku/render_density_test.dart` | 使用生产协调器、真实字体和渲染器，对照每桶4/8/12/16/24/32/120条、逐帧4/8条；30秒输入及8秒尾部，记录各权重可见率、面积时长、拥挤近似量、前沿积压和宿主开销。 |
| `danmaku/legacy_danmaku_rebuild_test.dart` | 测量旧弹幕渲染器在 120 个动画帧中的 widget 重建数和 pump 时间；重建数作为测量结果输出。 |
| `danmaku/baseline/` | 迁移前 Windows renderer/screen 及其专属回归；供像素、排轨、资源和预热对照，生产源码已统一使用窗口内核。 |
| `danmaku/frame_rate_matrix_test.dart` | 遍历屏幕刷新率、视频帧率和弹幕档位，输出合帧与更新统计；适合按需扩大时序诊断范围。 |
| `danmaku/frame_cadence_device_matrix_test.dart` | 将实测120Hz时序中的槽位抖动与回调迟到纳入Android模型，覆盖三种刷新率读数、五个弹幕档位、两种小数视频帧率及250ms/1秒批次，共60种组合；1秒批次和偶发5.7ms迟到为积压压力场景，20 至 31 ms 迟到由独立回归覆盖。 |
| `danmaku/frame_wake_lead_test.dart` | 在120Hz/60FPS下对比半屏到1.5屏的唤醒提前量与5/10/20/31.6ms迟到组合，输出最大间隔、长间隔和帧请求数；默认策略仍为半屏。 |
| `danmaku/frame_cadence_analysis.py` | 用 Python 标准库批量比较两份 `cadence.jsonl`，按连续播放段统计更新间隔、skip 截止推进、Timer 迟到和 FrameTiming；默认输出到 `build/frame-cadence-analysis/`。 |
| `danmaku/presentation_continuity_analysis.py` | 用 Python 标准库读取同帧对应的媒体位置和实际呈现时间，保留逐帧数值，汇总跨 1/2/3 帧的差分与 ±1/±2/±3（3/5/7 帧）局部波动，输出 JSON/CSV。 |
| [`android/`](android/README.md) | 隔离诊断包的 EGL 呈现时间与 FrameTimeline 对照，按 EGL 帧 ID 获取实际呈现并关联 Perfetto swap，核对连续性和按需输出成本。 |
| `danmaku/frame_rate_workload_test.dart` | 模拟同步更新耗时和额外 UI 帧，检查更新间隔及停止后的调度释放。 |
| `danmaku/native_video_frame_phase_test.dart` | 对照 Android 与隔离时序模型、mpv 同步和纹理相位，输出锁定状态检查。 |
| `windows/process_metrics_test.dart` | 在 Windows 上检查进程内存与 CPU 采样；其他平台会明确标记跳过。 |
| `diagnostics/redactor_benchmark.dart` | 对照普通日志、签名链接、长键名与重复 buvid 的脱敏耗时，可选读取本地 JSONL 诊断文件；只输出聚合统计。 |
| `diagnostics/memory_attribution_benchmark.dart` | 回放本地诊断目录，测量归属计算耗时与载荷大小；命令和范围见[诊断模块](../../lib/services/diagnostics/README.md#验证)。 |

测量使用 Flutter 测试宿主，pump 时间反映本机 CPU 侧重建和缓存状态；GPU 帧耗时在目标设备测量。主测试集保留 `test/pages/danmaku/frame_rate_ticker_test.dart` 和 `native_video_frame_sync_test.dart` 的核心调度与相位回归，扩大矩阵只在实验目录按需运行。

比较弹幕 CPU 热路径时，每种负载使用独立的测试进程，便于对照各自的峰值 RSS。

```powershell
foreach ($workload in 'selection', 'retention', 'merge', 'merge-close') {
  fvm flutter test --no-pub --reporter expanded --name "^${workload}$" tool/experiments/danmaku/cpu_hotpaths_benchmark_test.dart
}
```

固定输入预热三次后，输出九次耗时与中位数、结果校验值以及适用的保留字节数。峰值 RSS 统计整个 Flutter 测试进程。比较前后版本时，先核对校验值及保留字节数，再比较同一机器上的耗时。

日志脱敏基准使用独立 Dart 入口。比较发布模式 CPU 成本时，先编译 AOT，再运行同一组输入：

```powershell
fvm dart compile exe tool/experiments/diagnostics/redactor_benchmark.dart -o build/redactor-benchmark.exe
./build/redactor-benchmark.exe
./build/redactor-benchmark.exe <runtime.jsonl> <player.jsonl>
```

每项预热 3 次，再取 7 次测量的中位数。可选文件的测量包含生产脱敏和 JSON 重新编码，不包含文件读取、JSON 解码、快照协调和 ZIP 压缩；文件内容不会回显或改写。耗时用于同机对照，不作为自动化测试阈值；Android 设备速度需另行测量。

实际呈现分析的输入为已分段的 `presentation-stage-*.json`，包含 `summary`（`run/stage/target`）与 `matched` 数组；每帧字段为 `index/targetUs/positionUs/presentNs`，其中 `presentNs` 必须来自该弹幕更新帧的实际屏幕呈现。暂停、切档和媒体代次分别输入；缺帧、时间倒退和位置回退会中断窗口，首尾采用完整窗口，不补点。一般场景使用滚动＋顶部固定＋底部固定，覆盖固定弹幕进入、驻留和到期。

```powershell
python tool/experiments/danmaku/presentation_continuity_analysis.py <阶段1.json> <阶段2.json> --output build/presentation-continuity
python -m unittest discover -s tool/experiments/danmaku -p presentation_continuity_analysis_test.py
```

`--rate` 指定该测量段的媒体倍速，默认 1。省略 `--output` 时输出每阶段一行完整 JSON，可通过 PowerShell 管道保存。每个阶段独立保留逐帧值、跨 1/2/3 帧的跨度，以及间隔序列滞后 1/2/3 项的差分；±r 窗口包含 `2r+1` 帧和 `2r` 个间隔。窗口记录相对目标间隔误差、相对媒体速率误差的 RMS、呈现延迟极差及总位移速度，汇总数量、均值、分位数、峰值和速度偏差超过 10% 的诊断分桶。长短帧可能抵消窗口总误差，需结合窗口内 RMS 判断；重叠窗口的计数表示覆盖范围。`summary.json/summary.csv` 提供汇总，各阶段 JSON 保留明细。

文件排序复用实验默认生成 9000 条弹幕，对照三个固定 20 秒范围。可单独运行，并通过 `DANMAKU_FILE_ORDER_ELEMENTS` 扩大输入条数（至少 1500）：

```powershell
fvm flutter test --no-pub tool/experiments/danmaku/file_order_reuse_test.dart --reporter expanded
fvm flutter test --no-pub tool/experiments/danmaku/file_order_reuse_test.dart --reporter expanded --dart-define=DANMAKU_FILE_ORDER_ELEMENTS=12000
```

输出的 `DANMAKU_FILE_ORDER` JSON 行包含输入字节/条数、返回范围数量、解码扫描条数/批次数、耗时和排序产物复用/清理结果。计时包含排序构建或复用后的范围扫描及该次流读取退出，来源 store 最终 dispose 清理另行断言，排除测试文件生成和预期结果计算；耗时不作为测试阈值。这是 Flutter 测试宿主上的 CPU/磁盘成本对照，设备 RSS、GPU 和实际播放表现需要目标设备测量。

## 弹幕优先级与密度实验

在候选均可排入的条件下，显示名额按相对权重从高到低分配。例如12个名额面对权重0/3/5/7/10分别10/12/7/2/2条时，应显示权重10的2条、7的2条、5的7条、3的1条。同权重沿用来源次序，自己发送的弹幕优先于服务端权重。实验记录各权重的准入与显示分布；旧字段 `highAccepted/highDisplayed` 的≥8仅用于历史诊断，不能单独用来评判相对优先级。已建立的轨迹保持稳定，因此持续流还需比较跨桶的实际显示分布。

真实下载文件通过进程环境变量传入，原文件只读。报告只保存聚合数据；PNG含本地弹幕正文与视频画面，应保留在忽略的本地目录。

```powershell
$env:DANMAKU_REAL_FILES='<文件一>/danmaku.pb|<文件二>/danmaku.pb'
$env:DANMAKU_DENSITY_REPORT='build/danmaku-density/planner.json'
fvm flutter test --no-pub tool/experiments/danmaku/priority_density_test.dart
$env:DANMAKU_TEST_FONT='C:/Windows/Fonts/msyh.ttc'
$env:DANMAKU_RENDER_REPORT='build/danmaku-density/render'
fvm flutter test --no-pub tool/experiments/danmaku/render_density_test.dart
```

可设置 `DANMAKU_TEST_MERGE=1` 对照后台合并，`DANMAKU_TEST_FPS=30` 检查较低更新频率，`DANMAKU_TEST_CAPS=8,12,16`、`DANMAKU_TEST_PREPARE=8` 缩小配置矩阵，`DANMAKU_TEST_INPUTS=real1,real2` 选择输入。`DANMAKU_TEST_WINDOW=0/1/2` 选择按密度排序且互不重叠的前三个30秒真实范围。默认追加8秒空白尾部，避免范围末尾弹幕还未入画就停止统计；可用 `DANMAKU_TEST_TAIL_SECONDS` 调整。默认覆盖两份可选真实输入和四类合成素材：混合模式密集流、用户示例的持续流、全部权重较低的同分布流、固定12轨道的间隔脉冲。高级弹幕和用户屏蔽规则由正式回归覆盖。可在输出目录放置 `real1-background.png`、`real2-background.png` 作为本地视频背景。

耗时包括协调、测量、轨道布局和图片激活，不含视频解码、真实帧等待和离线拥挤计算。各权重记录原始条数、候选保留数、真正与视口相交的去重显示数、显示率、至少一半面积入画的条数、可见面积时长及入场延迟。包围盒拥挤率是几何近似，不代表文字像素遮挡率。桶内理想Top-N缺项以同桶实际显示数作参照；不同模式、字宽及已建立轨迹会使理想上界无法达到，不能将它当作排序错误率。性能比较应单独运行、重复观察，不设机器相关通过阈值。

生产预算见[默认构建与策略](../../doc/development/build-defaults.md)，实验矩阵按当前源码与输入选择。

```powershell
fvm flutter test --no-pub tool/experiments/danmaku/density_metrics_test.dart tool/experiments/danmaku/retention_budget_test.dart
python tool/experiments/danmaku/relative_density_analysis.py build/danmaku-relative-20261107
python -m unittest discover -s tool/experiments/danmaku -p relative_density_analysis_test.py
```

### 配置选择

候选上限和逐帧准备量需要同时比较相对权重保留、轨道利用率、准备积压及宿主开销。活动轨迹的持续占位会影响后续准入，减少候选不能保证所有输入都显示更多高权重弹幕，也不能单凭可见总数判断优先级。

来源缓存、显示窗口和图片工作集分别计量；放大缓存的收益需结合真实分段和持续压力输入判断。主机回放用于对照排序、几何与 CPU 成本，最终 GPU 呈现、Android 功耗和长期负载由设备测量。逐次配置、统计表和设备结果保存在本地 `doc/dev/`。
