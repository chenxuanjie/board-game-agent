# Android 后台更新与通知

2026-10-13：源码已接入。Dart 状态与失败测试、Android SDK 36 独立 Kotlin 编译检查用于验证接线；本轮不构建 APK。当前没有连接 Android 设备，切屏、熄屏、通知权限弹窗及系统安装界面的真机验收待执行，不能把源码检查当作手机实测。

## 执行方式

下载仍由现有业务组件拥有，不新增另一套下载或账号协议：

- 桌游资料：`AppController.applyPendingLibraryUpdate` → `RemoteAssetService` → 临时文件校验、缓存提交 → 重新加载目录。通知显示已完成项数/总项数；全部资源和目录重载成功后，才显示完成。失败保留待更新清单、已有缓存和重试入口。
- 安装包：`AndroidBackgroundUpdateService` 包装 `app_about`/`remote_update`，沿用 WebDAV 流式下载、与 SHA-256 绑定的断点文件、大小和 SHA-256 校验。通知显示真实字节进度、校验与准备阶段。通知传输失败不能把已提交的下载改报失败。
- Android 的 `DownloadProgressService` 只管理下载期间的 `dataSync` 前台服务、局部 CPU 唤醒锁和通知。它不持有 NAS 凭据、地址或文件，也不自行安装 APK。
- 开始下载必须先成功启动前台服务。下载途中切到其他应用不主动暂停、不关闭客户端；资料更新和 APK 下载分别维护通知，同一服务直到所有任务结束才释放。

采用 Android 官方的[前台服务启动方式](https://developer.android.com/develop/background-work/services/fgs/launch)、[dataSync 类型](https://developer.android.com/develop/background-work/services/fgs/service-types#data-sync)和[有界唤醒锁](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock)。没有引入新的第三方下载插件：当前共享更新器已经负责鉴权、续传、校验和安装边界，此处只补宿主执行与通知能力。

## 通知与权限

- 使用低重要性通知频道“资料与应用下载”，不循环响铃；资料和安装包使用独立的稳定通知 ID，重试覆盖对应旧通知。
- Android 13 起，在实际开始下载时请求[通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)。通知权限或下载频道关闭时，本次不开始下载，明确提示允许通知后重试；不反复在每分钟检查时请求权限。
- 点击进度或完成通知返回现有应用界面。完成/失败通知可清除，进行中的通知与前台服务绑定。
- 下载进度最多每 500 ms 发送一次；最终真实值不被节流。未知总量使用不定进度。通知仅显示任务类别、字节数或项数，不显示连接地址、凭据或账号资料。
- 通知栏进度属于实际更新下载；一分钟资源可用性/快速检查和安装包版本检查不启动常驻前台服务，不改变检查频率。

## 安装与失败边界

安装包完整下载并通过共享更新器校验后，下载服务结束，通知显示“安装包已校验，返回应用安装”。应用在后台时等待真实 `resumed` 生命周期；恢复后执行现有保存操作，再确认前台状态并启动系统安装界面。取消或释放服务后，过期等待不能重新启动安装。用户仍须授予现有未知来源安装权限并在系统安装界面确认；下载完成不代表安装完成。

- APK 下载保持共享包的 10 分钟超时及续传策略。
- 资料更新整次下载及目录重载共享 15 分钟截止时间。
- 安装前等待前台最多 15 分钟；超时保留已校验安装包，返回后重新检查/安装可复用它。
- 原生服务为每个任务提供 16 分钟安全截止时间；每次任务加入时更新有界唤醒锁，任务全部结束后释放。异常中断、系统前台服务超时和最近任务移除不留下“正在下载”的假状态。
- 权限、来源或账号改变、下载失败、校验失败、用户取消分别保留原业务的错误和重试边界。通知结束不代替缓存提交或安装包校验。

这是普通后台/切屏下载支持，不是独立持久化下载队列。Android 系统强行停止、划掉任务、进程死亡及部分厂商的省电限制仍可终止 Dart 下载；原生服务使用 `START_NOT_STICKY`，不会在下载所有者消失后启动空转服务。APK 部分文件保留供下次手动续传；资料清单重新检查后重试，不宣称应用被杀后能自动完整重建资料任务。

## 验收

本轮验证：`flutter analyze --no-pub` 无问题；全量 619 项测试通过；MainActivity/DownloadProgressService 使用 Android SDK 36、现有 Flutter embedding 和临时资源符号进行独立 Kotlin 编译通过；Manifest 和通知图标 XML 解析通过。这不是 Gradle 资源合并、APK 构建或真机验证。

自动测试覆盖：通知启动拒绝不开始下载；真实进度透传；校验失败不安装；后台校验完成等待前台；取消等待/准备后不安装；资料提交和重载后才完成；部分失败保留重试；通知入口失败不泄漏迟到服务。入口为 `test/android_background_update_test.dart`、`test/library_update_flow_test.dart`，Windows 更新用例同时回归。

真机仍需：分别开始资料与 APK 更新 → 切到其他应用两分钟 → 通知计数持续增长 → 返回应用对齐进度；APK 在后台下载完成时不抢前台，点击通知后可进入系统安装。另测拒绝通知、关闭频道、断网重试、资料与 APK 同时执行、取消、来源切换、熄屏、省电和划掉任务。实际 APK 的权限合并及资源精简检查须在用户明确要求构建后执行。
