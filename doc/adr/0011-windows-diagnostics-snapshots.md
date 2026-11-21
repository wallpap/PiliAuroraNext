# Windows 诊断采样只发布聚合快照

PDH 查询先按当前进程过滤，避免格式化随后会被丢弃的全系统 GPU 样本；十六进制适配器标识统一格式再与 DXGI 匹配。原生通道接受 `StandardMessageCodec` 对小整数的 32 位表示。

虚拟内存采样只扫描本进程的映射和保护元信息，不读页内容、不查文件名、不输出地址。控制线程启停，其他线程读取缓存；RW 与 WRITECOMBINE 互斥，保护修饰位单列。`sample_id` 标识本次快照差分，不是累计事件日志；短命分配和两次观察之间的变化可能不可见。

不完整扫描不宣称未遍历项已释放。已跟踪的大块在观测到消失前保留身份，低于阈值仍标记跟踪，新候选按大小进入有界集合；重新启用时清空映射但不复用数值 ID。入口见 [`memory_metrics.h`](../../windows/runner/memory_metrics.h)、[`memory_metrics.cpp`](../../windows/runner/memory_metrics.cpp) 和[Windows 性能排查](../maintenance/troubleshooting.md)。
