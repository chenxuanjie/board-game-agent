# Windows 与 Android 应用内更新

两端共用 app_about 的 WebDavAppUpdateService 和 AppUpdateContent：检查版本、显示更新说明、下载进度、校验、取消、失败重试与安装入口只有一套实现。remote_update 继续负责通用清单/版本/流式下载/大小与 SHA-256 校验及平台安装器，remote_update_webdav 继续负责 WebDAV 传输。没有新增平行包，也没有保留两套更新引擎。

## 平台入口与清单

桌面设置中的“检查 Windows 更新”直接进入关于页并启动检查，不再需要再点击一次。关于页显示 Windows 安装包（EXE）；Android 显示 APK。版本读取来自 PackageInfo，未知版本不会用旧 build 猜测更新。pubspec.yaml 是构建版本唯一来源。

原生工厂使用 Platform.isWindows / Platform.isAndroid，独立于 UI Theme 或 Web 的桌面布局。Web 不展示可执行的 Windows 更新按钮，也不会下载、执行安装程序。

- Windows x64：apps/board_game_agent/updates/windows/x64/manifest.json；只接受 Windows x64 EXE。
- Android：apps/board_game_agent/updates/manifest.json；按实际 ABI 选择 APK。
- 两端均只接受当前 appId、stable 通道的较新 build；拒绝跨平台、错误架构、不安全路径及错误文件类型。
- 使用登录派生的资源连接，多个受信任入口并发检查、首个有效目标清单胜出。任一入口失败不会阻止另一个入口；连接/账号变化后必须重新检查。

## 下载、恢复与安装

HTTP 只允许 HTTPS（回环地址仅用于测试），不绕过 TLS。Windows 的环境/系统代理仍通过 app_ai_client 的既有原生客户端工厂注入，Android 也由应用注入同一工厂；老 Android 工厂的额外证书加载接口保持兼容。不记录原始服务器错误、凭据或令牌。

每个请求有超时，单次下载最多 10 分钟；可暂停下载，暂停、断网、超时或应用关闭后保留已写入的部分。缓存保存在应用支持目录，按安装包 SHA-256 绑定临时文件；下次重试或重启后重新检查清单，再通过 HTTP Range 从已保存字节继续下载。验证 206 与 Content-Range 的起止范围、总大小和剩余长度；服务器忽略 Range 或返回 416 时安全重下，不把完整响应拼接到旧数据。短流保留，已确认大小异常或 SHA-256 不通过的文件才清除；完整包经全量校验后才启动安装器。

安装失败可复用已完整校验的缓存，界面重试会重新检查清单。更新说明独立滚动，进度和主按钮固定，阶段分别显示下载、校验、准备和启动安装程序；失败后显示继续下载、重试更新或重试安装。下载期间禁止通过返回键或点击弹窗外部意外关闭更新流程，可先暂停再离开。

程序启动检查、版本提示及关于页更新流程持有共享的资料提示暂停状态，结束后才恢复资料提示；后台发现的资料更新仍保留待处理记录，不会被误标为已读。资料弹窗在实际打开前再次检查暂停状态和当前路由，后台页面、系统安装器覆盖期间不抢占前台。

断点响应处理参考 [HTTP Semantics（RFC 9110，Content-Range）](https://www.rfc-editor.org/rfc/rfc9110.html#section-14.4)，暂停实现遵循 [Dart StreamIterator.cancel](https://api.dart.dev/dart-async/StreamIterator/cancel.html)，会取消流订阅并释放等待中的读取。

安装前等待应用既有写入队列完成（15 秒上限）；正在回复、录音或保存设置时可重试，不强制终止这些操作。WindowsUpdateInstaller 再次验证大小、SHA-256 和 MZ 文件头，以 Process.start 参数数组启动 Inno，不使用 shell，不强制关闭应用或重启系统。识别 unins000.exe 后将原安装目录交给 Inno；开发/便携运行使用普通安装向导。只有安装器成功启动后才调用 windowManager.destroy；失败保持当前程序打开。

安装包包含完整 EXE、DLL 和 data，不能单独分发 runner EXE。Inno 保持稳定 AppId，保留 AppData 设置、聊天及缓存。当前发布包尚无 Authenticode，SHA-256 表示完整性校验，不代表发布者签名。

## 历史验证（4.0.0+30）

主项目 456 项回归通过，既有 23 项 Windows 更新验收保持通过；公共 UI/服务包 32 项、更新内核 12 项测试通过。验收包括目标隔离、连接更改、双入口、超时、损坏文件、取消下载、缓存重试、未知来源权限、启动强制更新与普通更新、长说明/窄窗口及安装交接。权限对话框或磁盘校验结束后、启动安装器前再次检查服务未销毁和连接未改变，拒绝离开页面后的晚到安装请求。未生成渲染测试图片。

通过真实群晖读取 Windows 清单，重新下载 build 26 的 161491344 字节 EXE 并完整校验，再交给独立验收接收器；没有真正执行此安装器或关闭用户程序。Windows Release 在 C:/bga-update-validation 独立目录编译通过，版本 4.0.0+30；JavaScript Web 编译也通过并保留既有 Wasm/字体预检告警。Android 本轮验证共享路径及安装权限接口，未进行实机安装。

本轮未生成或推送新安装包；远端已发布 Windows 清单仍指向 build 26。后续发布必须用完整 Windows 安装包，经远端 SHA-256 和不可变记录确认后最后切换清单。回滚源码可还原本轮提交；已发布程序需要用更高 build 发布恢复版，不能把清单指回更低 build。

## 下载恢复与提示隔离验证（2026-10-08，4.1.0+31）

主项目静态分析通过，505 项测试通过；共享包 remote_update 20 项、remote_update_webdav 7 项、webdav_storage 14 项、app_about 35 项测试通过。新增验收覆盖断网和短流保留、暂停卡住的流、重启后的断点恢复、完整缓存直接校验、不同 SHA-256 不混用、错误范围拒绝、Range 不支持时安全重下、安装重试，以及资料提示的嵌套暂停和延后显示。

真实 NAS 只读请求验证 Android build 30 和 Windows build 26 的安装包均支持 `Range: bytes=1024-`，返回 206、正确的 Content-Range 和总大小；每次仅读取 16 字节后关闭连接，没有写入或发布远端文件。该验证证明传输入口支持续传，不等于 Android 实机完整升级验收。

Android Release 构建成功，APK 143.31 MiB，资源检查发现禁止打包的桌游文档 0 项。Windows 默认输出被正在运行的程序锁定，保留原进程后在 `build/update-recovery` 隔离构建成功，文件版本为 4.1.0+31；Flutter 的全局构建目录配置已恢复。此次只生成本地产物，没有生成新的 Windows 安装器或上传 WebDAV，也没有执行 Android 实机安装。

仍待改善：没有系统后台下载任务和下载通知；应用被系统结束后需重新进入更新页面继续。没有有界自动重连、移动数据下载确认和磁盘空间预检，目前磁盘错误会提示处理后重试。旧版本残留缓存尚无管理入口。普通断网、暂停、超时不清除当前有效进度；已确认损坏的文件必须重新下载。

本轮提交记录（主项目与共享包分别保存）：

| 仓库 | 分支 | 提交 | 标题 |
| --- | --- | --- | --- |
| board-game-agent | codex/synology-direct-auth | 821a430 | fix(update): 延后资料提示并接入安装包续传 |
| remote_update | codex/pre-syno-auth-20261005 | fc76cec | fix(update): 保留中断下载并支持重启续传 |
| remote_update_webdav | master | e3bcafa | fix(update): 验证断点范围并兼容服务器重下 |
| webdav_storage | master | 85dc07f | fix(webdav): 及时关闭不支持断点的下载响应 |
| app_about | codex/pre-syno-auth-20261005 | 4b3e3c8 | fix(update): 完善暂停续传与更新界面反馈 |
