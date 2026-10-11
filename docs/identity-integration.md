# 群晖直连登录

Android / Windows → HTTPS `SYNO.API.Auth` v6 → NAS 验证账号密码。
无需 Supabase、SSO 应用注册或新增会话服务。群晖要求双重验证时才显示验证码。
Web 不尝试直连认证，继续使用访客功能。

公共包 `app_identity` 0.3.0 与主项目均使用 `codex/synology-direct-auth` 分支。
运行路径依赖时必须同步切换公共包；只切主项目会造成接口不兼容。

## 入口与默认连接

手机“我的” → 账号，或三端设置 → 账号。原生端填写群晖用户名、密码即可。
默认 DSM 地址 `https://cznas.dpdns.org:5001`；5006 是 WebDAV，不用于账号认证。
公开地址可由编译参数 `SYNOLOGY_ORIGIN` 指定，不包含账号密码。
用户账号密码不作为程序默认配置或构建参数，不写入 Git。

## 代码归属

- 公共包 `../shared_packages/app_identity`：直连接口、状态机、取消请求、安全存储、恢复与退出。
- `lib/features/identity/`：默认 NAS 配置、平台能力、生命周期验证与个人数据作用域。
- `lib/ui/shared/account_screen.dart`：共用账号页；Web 显示不支持登录并保留访客访问。
- `integration_test/direct_synology_auth_test.dart`：真实原生网络、系统安全存储、重建适配器恢复、退出后旧会话失效验证。

先用 `SYNO.API.Info` 发现接口。密码只放在 HTTPS POST 请求体中，禁止重定向。
登录后用 `SYNO.FileStation.Info.get` 获取并验证数值 UID；控制器再次独立验证才进入正式登录状态。
当前 NAS 的验证与退出需要 GET `_sid`，完整 URI 含凭据，不写入诊断日志。错误使用固定、脱敏的类型与文案。
单请求限时 12 秒，响应上限 64 KiB，安全存储等待限时 10 秒；登录不自动重试。

## 数据与会话

应用身份以固定 HTTPS NAS origin 与验证后的 UID 生成。账号名仅作显示，不用于认领旧数据。
收藏、最近浏览、AI 会话使用独立账号命名空间；切换前排空旧写入，完成后展示新账号数据。
访客和此前 Supabase / 服务方案的数据不自动合并。Android / Windows 已接入个人账号云同步，范围与私有目录见 [账号云同步](account-cloud-sync.md)。
新配置使用 v3 键，系统安全存储使用 synology-direct:v1 命名空间；旧配置不参与直连登录。

SID、SynoToken、UID 仅写系统安全存储，密码与 OTP 不保存。安全存储不可用时拒绝登录，不回退明文。
重启 / 返回前台时验证会话，前台每分钟验证一次。离线缓存身份仅供本机显示，不构成服务端权限证明。
退出先持久化退出标记、撤掉本地身份；断网时只保留加密会话用于下次前台补偿，重启不得恢复旧身份。

## 直连方案限制

- NAS 必须能通过有效 TLS 证书的 HTTPS 地址访问；NAS 不可用时不能建立新登录。
- 保存的是群晖会话，权限来自 NAS 账号，不是权限受限的应用令牌。普通账号须有 FileStation Info 权限；应用不自动提升权限，仅访问本应用的私有同步目录，不遍历其他个人文件。
- 会话过期需重新输入密码；未实现独立应用刷新令牌、应用级角色、全设备退出或后台撤销服务。一个设备退出不影响其他设备。
- 断网退出的远端撤销在程序再次运行并联网后完成。如果登录响应丢失而 NAS 已创建会话，客户端不知道 SID，只能等 NAS 过期或管理员撤销。
- NAS origin 改变会形成新数据命名空间；删除重建 NAS 用户时 UID 可能复用，不能在未处理旧数据时把同一 UID 当成新用户。
- 当前 Web 被禁用。原生共享逻辑不能绕过浏览器 CORS；不将 NAS token 放入浏览器 localStorage。

保存 / 回滚见 [认证保存点](identity-preservation.md)，验收范围见 [验证记录](identity-validation.md)。

协议参考：[DSM 登录 API](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf)、[File Station API](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/FileStation/All/enu/Synology_File_Station_API_Guide.pdf)。
