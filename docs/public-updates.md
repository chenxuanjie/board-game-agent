# 游客程序更新

阶段 P1、P2 源码：程序发布与资料发布采用独立版本；源码状态、已发布版本与部署验收分别确认。

Android、Windows 默认通过应用服务的公开 `/v1/apps/board_game_agent/releases/manifest` 和摘要文件入口更新。无需登录、NAS 密码或后台专用用户；退出、刷新或切换账号不影响升级。更换服务地址会使旧检查结果失效。未配置服务地址的新安装使用公开参数 `APP_SERVICE_ORIGIN`，默认 `https://cznas.pp.ua:18281`。该地址不是凭据。

`app_client/updates.dart` 的 `PublicReleaseSource` 只接受同一 origin 的摘要工件路径，匿名读取，不接受外部下载 URL。原生更新复用 app_about 的 `NativeAppUpdateService` 和 remote_update：目标选择、续传、大小及 SHA-256 校验、Android 安装许可、Windows 安装器和取消。Android 保留已有后台传输通知及回前台安装流程。Web 没有安装器入口。

WebDAV 更新实现保留为 `createBoardGameWebDavUpdateService`，不是默认来源，不在服务失败时自动执行。相关设置与公共包暂时保留；本阶段不清理旧账号/资料业务。

发布协议见后台 `docs/public-releases.md` 和 publisher skill 的 `references/service-delivery.md`：

```powershell
# 默认新服务：不构建、不上传，只检查已有包并预览
pwsh -NoProfile -File scripts/package-app-release.ps1 -Target android -Mode push -DryRun

# 显式备用：原 WebDAV 发布，不自动双写
pwsh -NoProfile -File scripts/package-app-release.ps1 -Target android -Mode push -Destination webdav -DryRun
```

Windows 使用 `-Target windows`。正式上传仍须来源门禁及授权。修改源码不代表新 API 已部署或安装包已登记；首次发布前应显示“尚未发布当前平台的更新”。

## P2 公开发布通知

复用现有游客公共 PowerSync 连接，订阅 `core.publication_versions`。后台在程序发布事务中更新应用、通道、平台和架构对应的最新构建水位；上传但未发布、发布失败或事务回滚不通知。资料发布有独立 catalog 水位。通知只用于触发既有权威 API 读取，不能携带自定义下载地址或绕过摘要校验。

新安装未手填服务地址时使用上述公开默认地址，游客即可建立公共订阅；不配置共享升级账号。登录、退出和换账号仍可重新建立公共连接，未登录同样能收到公共变化，私人同步仍独立授权。

原生收到 stable 通道、当前平台的程序信号后，通过已有更新服务检查设备适用性。确认有可安装的新版本后，在应用消息中心显示“发现新版本”；同版通知去重，点击进入更新页。不会自动下载或安装；“检查程序更新”开关关闭时不进行这项后台检查，再次开启会补读公共水位。Web 不运行原生安装检查。

资料和社区、程序检查分别尝试，一项失败不阻塞其他项；失败任务合并后最多追加五次指数退避，后续通知、回前台或重连可再次触发。后台/隐藏期间断开公共连接并停止刷新计时器，前台恢复后补齐。该能力依赖应用运行与连接，不等同于手机/Windows 系统推送。

上线需要新 API 镜像（迁移头 `0017_publication_versions`，接在 P1 的 `0016_release_architecture` 之后）、含 `public_publication_versions` 的 PowerSync 规则和新 APK/EXE。现有 Docker 打包器会把新规则写入配套 Compose，保留数据库、签名及挂载配置；PowerSync/PostgreSQL 镜像版本无需因此变动，但 PowerSync 容器需要应用新配置。不得单独部署规则到尚未迁移的新表之前。

恢复并衔接 P1 后，本机 `flutter analyze --no-pub` 通过，`flutter test --no-pub` 完整 572 项通过，覆盖通知合并、暂停/恢复、失败重试、来源切换、工作区切换与迟到结果、平台过滤、资料补齐及通知过程不下载安装。后端完整 334 项测试通过；真实 PowerSync 1.27.0 隔离探针通过匿名快照、事务发布后收敛、重连补读及跨应用隔离。测试并不代表 Android/Windows 安装产物或 NAS 已验收。

## P1 修复与 P2 恢复（2026-10-29）

P1 的通用 APK 架构已统一为 `any`。API 迁移 `0016_release_architecture` 修正旧索引和约束，保留不可变来源记录及安装包字节，不接受 universal 别名；客户端保留通用包进入 arm64 安装流程的回归用例。

发布器上传前匿名检查目标清单；配置缺失或 API 拒绝目标时立即失败，404 允许首次发布。打包器检查独立可写安装包卷和发布密钥摘要。API 0.5.1、提交 `a6c9db3` 已发布 GHCR，配套 Compose 已包含发布配置；本机使用真实 5.0.0+47 APK 验证流式上传、SQL 发布、匿名下载、摘要、Range 和重启持久性。NAS 实际安装验收与本机 Docker 验证分别记录，不沿用旧的 503/架构未统一结论。

已恢复客户端与后台 P2 暂存，将发布通知迁移顺接为 0017，并保留 P1 的 `any` 契约。账号工作区切换立即使正在执行的程序检查失效，迟到结果不能写入新工作区或消耗其通知水位。既有 47 APK 和 API 0.5.1 不因此自动获得 P2 能力；实际交付和部署以对应构建及现场结果为准。
