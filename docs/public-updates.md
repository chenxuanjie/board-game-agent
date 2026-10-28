# 游客程序更新

2026-10-28，阶段 P1 源码改造。程序发布与资料发布采用独立版本；资料定时检查和发布通知留待 P2，本阶段未改动。

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
