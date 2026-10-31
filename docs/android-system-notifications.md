# Android NAS 实时更新提醒

用户可开启 NAS 实时提醒。应用使用单独的 Flutter 后台引擎和独立的公开 PowerSync 数据库订阅已有发布水位，不读取账号或密码，也不扫描资料文件。未登录可以使用；手机必须能够连接所配置的 NAS 应用服务及其 PowerSync 入口。

- 设置中开启“NAS 实时更新提醒”；Android 13 及以上需要通知权限。开启后系统显示一条持续存在的“桌游导师正在接收 NAS 更新”通知。关闭开关会停止后台服务。
- 网络及服务正常且后台服务存活时，发布变化经 PowerSync 传送；断线后由 PowerSync 重连及恢复公开水位。并不保证即时或必达，设备离线、强行停止、系统回收、厂商省电及连接故障均可能中断；重新打开应用可再次尝试启动。首次资料水位建立基线，不把现有资料当作新发布。
- 面向 Android 15 或更高版本的应用，其 `dataSync` 前台服务在后台受系统六小时限制，且下载服务共享同一类型的预算；到期后服务会停止。不得借用不符合用途的服务类型来规避系统限制。
- 发布新资料或适用于本机的 Android 程序版本时显示独立通知，标题标记“NAS 实时连接”；同一来源同一版本不重复提示。关闭“检查程序更新”后仅停止程序版本提醒。通知不自动下载或安装。
- 测试时预期并行的 Google FCM 通道尚未接入；当前不能比较两条通道的到达情况。没有通用公告、评论回复、私人消息或 Windows 关闭后的系统推送。
- 使用现有公开 PowerSync 订阅及后台接口；本次 NAS 通道无需修改 FastAPI、数据库、Compose 或 PowerSync 规则。需要重新构建 Android APK；后台存活、断线恢复和系统通知尚须在实际手机和 NAS 上验证。

具体限制以 Android 官方的 [前台服务时长限制](https://developer.android.com/develop/background-work/services/fgs/timeout) 与 [通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission) 为准。
