# 让启动故障可报告且不暴露原始异常正文

异常捕获始终随应用装配，不按启动时的日志等级跳过，才能在运行中即时切换记录级别。主窗口由装配层展示错误页；播放子进程直接以失败状态退出。启动失败页不读取存储、配置或账号，确保错误发生于存储就绪前也能展示并以失败状态关闭进程。在桌面上先等待 `waitUntilReadyToShow`，再逐步等待显示和聚焦；不把异步操作放进不会被等待的 `void` 回调中。

内部故障保留原始原因和堆栈；用户可复制的摘要只输出阶段、异常类型、适用的系统错误码和脱敏堆栈。不输出原始异常正文，因为可能包含账号、路径或 IPC 凭证。Android 原生调用错误同样不把可能包含 Intent 或地址的原生异常正文交付给用户。入口见 [`startup.dart`](../../lib/app/startup.dart)、[`startup_failure.dart`](../../lib/app/startup_failure.dart)、[`bootstrap.dart`](../../lib/app/bootstrap.dart) 和 [`android_helper.dart`](../../lib/platform/android/android_helper.dart)。
