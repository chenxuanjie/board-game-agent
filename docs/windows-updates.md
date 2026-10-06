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

每个请求有超时，整包下载最多 10 分钟；可取消下载，离开页面会取消网络请求。下载失败或校验不通过不启动安装器；安装失败可复用已完整校验的缓存，界面重试会重新检查清单。更新说明独立滚动，进度和主按钮固定，阶段分别显示下载、校验、准备和启动安装程序。

安装前等待应用既有写入队列完成（15 秒上限）；正在回复、录音或保存设置时可重试，不强制终止这些操作。WindowsUpdateInstaller 再次验证大小、SHA-256 和 MZ 文件头，以 Process.start 参数数组启动 Inno，不使用 shell，不强制关闭应用或重启系统。识别 unins000.exe 后将原安装目录交给 Inno；开发/便携运行使用普通安装向导。只有安装器成功启动后才调用 windowManager.destroy；失败保持当前程序打开。

安装包包含完整 EXE、DLL 和 data，不能单独分发 runner EXE。Inno 保持稳定 AppId，保留 AppData 设置、聊天及缓存。当前发布包尚无 Authenticode，SHA-256 表示完整性校验，不代表发布者签名。

## 本轮验证

主项目 456 项回归通过，既有 23 项 Windows 更新验收保持通过；公共 UI/服务包 32 项、更新内核 12 项测试通过。验收包括目标隔离、连接更改、双入口、超时、损坏文件、取消下载、缓存重试、未知来源权限、启动强制更新与普通更新、长说明/窄窗口及安装交接。权限对话框或磁盘校验结束后、启动安装器前再次检查服务未销毁和连接未改变，拒绝离开页面后的晚到安装请求。未生成渲染测试图片。

通过真实群晖读取 Windows 清单，重新下载 build 26 的 161491344 字节 EXE 并完整校验，再交给独立验收接收器；没有真正执行此安装器或关闭用户程序。Windows Release 在 C:/bga-update-validation 独立目录编译通过，版本 4.0.0+30；JavaScript Web 编译也通过并保留既有 Wasm/字体预检告警。Android 本轮验证共享路径及安装权限接口，未进行实机安装。

本轮未生成或推送新安装包；远端已发布 Windows 清单仍指向 build 26。后续发布必须用完整 Windows 安装包，经远端 SHA-256 和不可变记录确认后最后切换清单。回滚源码可还原本轮提交；已发布程序需要用更高 build 发布恢复版，不能把清单指回更低 build。
