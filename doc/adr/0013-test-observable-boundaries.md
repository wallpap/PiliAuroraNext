# 用独立观察验证异步和绘制边界

标题栏提示须检查实际绘制，组件在树中不等于它没有被遮住；迟到的初始窗口查询不能覆盖已到达的窗口事件。应用壳的诊断用例在退出前排空通知的合并窗口，测试需区分生产故障与测试框架在结束时发现的遗留定时器。

区域解码以独立的 Flutter 完整帧为参照，不用区域后端证明自己正确。ICC 源可能使原始图像字节仍处于源空间，所以先经 Flutter 绘制再比较显示像素。同一模拟时间区内复用来源队列，不让 Future 跨越已结束的 `FakeAsync`。订阅泄漏用整段静默期测量，避免新输入刚好取消旧计时器而掩盖泄漏。

依赖检查的夹具用 JSON 表示 YAML，避免把夹具缩进错误误作策略失败；清理只删除本次测试独占的系统临时目录。入口见 [`desktop_title_bar_test.dart`](../../test/app/desktop_title_bar_test.dart)、[`native_fidelity_test.dart`](../../test/common/widgets/image/native_fidelity_test.dart) 和 [`dependency_policy_test.dart`](../../test/architecture/dependency_policy_test.dart)。
