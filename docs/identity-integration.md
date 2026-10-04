# 群晖账号登录

当前方案：三端账号/密码 → 应用会话服务 → `SYNO.API.Auth` v6 → 群晖验证。
群晖要求双重验证时才显示验证码。普通用户不填写 Supabase、OIDC、客户端 ID 或回调地址。

公共包 API 版本为 `app_identity` 0.2.0，Git 提交 `56fe682`；应用采用相邻路径依赖。复现时需将该包切到 `codex/synology-auth`，不能只切主项目而仍使用旧 0.1.0 包。

## 代码归属

- 公共包 `../shared_packages/app_identity`：认证状态机、可取消请求、Web Cookie/CSRF、原生安全存储、恢复和退出。
- `lib/features/identity/`：可信登录服务地址发现、生命周期验证、应用个人数据命名空间切换。
- `lib/ui/shared/account_screen.dart`：三端共用账号页，设置/“我的”的账号入口进入。
- `server/identity_web/`：三端共同使用的 Node 24 会话服务，不仅服务 Web。
- `scripts/identity/probe_auth.mjs`：操作员真实 NAS 集成验证，不是应用登录页面。

服务通过 `SYNO.API.Info` 发现接口路径，密码只在 HTTPS POST 请求体中提交。
成功后用 `SYNO.FileStation.Info.get` 验证真实 UID，并以固定 NAS 标识和 UID 生成应用用户 ID。
输入的用户名仅作显示名，不能用于决定数据归属。当前 NAS 的会话验证/退出需 GET `_sid`；禁止将完整出站 URI 写入日志。

## 数据与权限

收藏、浏览、AI 会话等沿用现有账号命名空间；切换前排空上一账号的写入，完成后才展示新账号数据。
访客数据不会自动并入账号，旧 Supabase 用户也不会按相同用户名自动匹配。
旧认证配置保留但不参与新登录；新配置键和安全存储使用独立版本/服务命名空间。

此功能验证群晖账号并管理应用会话，不等于已有跨端个人数据云同步，也不自动授予 NAS/WebDAV 资料权限。
WebDAV/AI 连接设置保持原有功能，不能用共享 WebDAV 密码代替每个用户的登录身份。
服务只调用认证和 UID 接口，不获取用户文件内容。用户必须有 FileStation Info API 权限；无权限则拒绝登录。
NAS 删除并重建用户时 UID 可能被复用，管理员须先撤销旧绑定/处理旧数据，不能直接把旧数据交给新用户。

## 保存点与回滚

见 [认证保存点](identity-preservation.md)。恢复时同时切换主项目与公共 `app_identity` 到对应保存分支，执行 `flutter pub get`。
不要复用当前加密会话数据库或迁移登录凭据；其他公共包保持保存提交。

协议参考：[DSM 登录 API](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf)、[File Station API](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/FileStation/All/enu/Synology_File_Station_API_Guide.pdf)。
