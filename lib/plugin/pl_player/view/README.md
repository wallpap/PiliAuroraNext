# 播放器展示与交互

`PLVideoPlayer` 是点播、直播和独立播放窗口共用的展示入口。它按顺序装配画面、弹幕、字幕、遮罩和控件，并同步控制条动画、时间电量和字幕避让。播放意图与加载状态仍以 `PlaybackSession` 的快照为准，约束见[播放状态模型](../../../../doc/development/playback-model.md)。

## 修改入口与所有权

| 文件 | 职责与资源 |
| --- | --- |
| [view.dart](view.dart) | 图层顺序、控件可见性和页面参数装配；创建并释放展示协调器 |
| [video_controls.dart](video_controls.dart) | 点播控制菜单、上下集、选集、画质、字幕与倍速；保留页面和媒体归属检查 |
| [player_gestures.dart](player_gestures.dart) | 鼠标、触摸和触控板输入；持有手势识别器、缩放矩阵、系统亮度/音量监听及亮度提示计时器 |
| [scale_restore.dart](scale_restore.dart) | 还原缩放按钮及动画 ticker；退出组件时取消动画 |
| [danmaku_actions.dart](danmaku_actions.dart) | 弹幕选择、菜单定位、复制、举报、点赞和跳转；持有规则监听，不持有显示实例 |
| [video_output.dart](video_output.dart) | 输出尺寸订阅、诊断、保护帧和绘制屏障；借用运行时的 VideoController，不创建或销毁 Player |
| [webp_capture.dart](webp_capture.dart) | 动态截图对话框、转码和保存流程；整次操作绑定页面、owner 和媒体代次 |
| [video_progress.dart](video_progress.dart) | 控制条与精简进度条共用的进度、分段和高能轨道，保留各自的命中范围和显示偏好 |
| [seek_preview.dart](seek_preview.dart)、[video_time.dart](video_time.dart)、[player_indicators.dart](player_indicators.dart) | 预览图句柄、时间绘制与操作反馈；预览图按加载代次交付并延后释放旧图 |

这些文件各自成库，依赖通过构造参数或窄回调传入。子模块不导入 `view.dart`。输入与输出协调器不直接读取业务页面、HTTP 或全局存储；点播菜单和截图保留现有页面适配，后续业务迁移从这两个入口继续。

## 交互约束

- 桌面单击切换播放，双击切换全屏。右键与中键在抬起后提交全屏目标，取消事件丢弃挂起操作。锁定全屏时，右键退出先解除锁定。
- 触摸双击按左、中、右区域分派。长按在结束或取消时恢复倍速；滑动进退在松开后提交，直播不提交 seek。锁定状态和滚轮音量沿用各自规则。
- 弹幕命中会消费本次点击。选择在抬起前失效时，也不能把同一次点击转为控制条操作。规则变化撤销选择；没有有效视频时长的弹幕不提供时间跳转。
- 画质应用成功后才显示提示、判断网络并保存默认值。每个异步阶段核对页面、媒体数据和播放归属；失败后的相同画质仍可重试。
- 动态截图操作属于整个播放器视图。隐藏控件或退出全屏不会中断已开始的操作；离页或更换页面归属时取消。取消不代替转码退出和文件消费屏障。
- 输出保护图先进入绘制场景，再修改几何，获得替换帧确认后撤图。输出与输入协调器在视图退出时释放自己的监听、图片和计时器，Player 继续由运行时释放。

图层顺序由 `view.dart` 集中维护。移动反馈或加载遮罩时，检查弹幕菜单、字幕、控件和首帧等待之间的覆盖关系。

## 验证

```powershell
fvm flutter test --no-pub test/plugin/pl_player test/pages/video test/architecture
fvm flutter analyze --no-pub lib test tool
```

展示回归直接驱动控制条、鼠标/触摸事件、触控板、进度条和还原按钮。输出交接与动态截图的可控回执分别在 `test/plugin/pl_player/video_output/` 和 `webp_capture_operation_test.dart` 验证；CI 范围见[测试入口](../../../../tool/run-ci-tests.ps1)。

主机测试覆盖事件分派、异步归属和资源释放。Android 系统亮度、Surface/MediaCodec，以及 Windows 原生全屏、GPU 纹理和实际声音仍需目标设备验证，方法见[平台探针](../../../../tool/probes/README.md)。
