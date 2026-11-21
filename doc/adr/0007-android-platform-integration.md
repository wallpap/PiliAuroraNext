# 通过系统边界接入 Android 能力

- 文件由系统选择器交付，图片通过 MediaStore 写入；现代路径不要求媒体库读取权限，manifest 仍保留分版本的旧存储声明。账号、缓存和本地设置不进入云备份或设备迁移。系统、车机和媒体客户端需要绑定 `MediaBrowserService`，不加应用私有权限。第三方域名的链接处理由用户授权，而非宣称应用可以验证这些域名。
- 保留旧返回键分发。Flutter 初始化前后分别使用 Android 的 `LaunchTheme` 和 `NormalTheme`；区分深浅色与系统 splash 实现，保留 Flutter embedding 元数据以生成插件注册器。Profile 构建的 Internet 权限也供 Flutter 工具连接。
- Android 的包可见性可能让预查询看不到仍可启动的扩展；直接尝试启动并报告失败，不新增广泛的包查询权限。JNI 画中画入口没有播放器的窗口坐标，使用当前可见内容作为过渡边界；后台或尚未布局时省略空矩形，沿用系统动画。切换桌面入口时先启用目标项，保证逐项更新也不会暂时失去入口。
- Gradle 使用环境中的 JDK 25，不固定本机目录或厂商；应用和 Flutter 插件对齐 Java/Kotlin 目标。应用测试包采用可与正式版并存的包名，并排除插件额外补入的 ABI。应用的 Flutter Gradle 插件须在 Android 和 Kotlin 插件之后应用。
- Linux CI 不复用 Gradle 目录监听状态，以避开路径被重复注册；插件下载的原生 JAR 缓存在项目 `build/`，不属于 Gradle 用户缓存。
- `android/lint.xml` 仅抑制已经核对的警告：`local.properties` 的转义由 Flutter 写入、由 Gradle 的 `Properties` 读取，不改写生成属性；同像素尺寸的启动图标与 splash 具有不同逻辑密度，不能复用同一资源。

入口见 [`AndroidManifest.xml`](../../android/app/src/main/AndroidManifest.xml)、[`AndroidHelper.java`](../../android/app/src/main/java/com/wallpap/piliauroranext/AndroidHelper.java)、[`app/build.gradle.kts`](../../android/app/build.gradle.kts) 和 [`lint.xml`](../../android/lint.xml)。签名与环境配置见[构建与测试](../development/build-and-test.md)。
