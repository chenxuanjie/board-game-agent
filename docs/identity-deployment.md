# 直连方案无需部署登录服务

当前 Android / Windows 已直接连接 `https://cznas.dpdns.org:5001` 的 `SYNO.API.Auth`。
无需 Node、容器、应用数据库、Supabase 或新增反向代理。
正常使用仅需在账号页输入本人的群晖账号密码；需要双重验证时输入验证码。

前提是现有 DSM HTTPS 接口可访问且证书有效，账号有 FileStation Info 验证 UID 的权限。
不自动修改 NAS 权限、关闭 TLS 校验或存储用户密码。Web 继续以访客模式运行。
如需更换 NAS，可通过公开编译参数 `--dart-define=SYNOLOGY_ORIGIN=https://NAS域名:5001` 指定。
更换 origin 会改变账号数据作用域，不能自动把旧 NAS 的同名用户数据迁入。

上一版需要部署的会话服务保留在 `codex/synology-auth` 分支；其部署步骤只适用于该保存分支。
当前实施与限制见 [直连登录](identity-integration.md)。
