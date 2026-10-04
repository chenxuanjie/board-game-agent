# 三端账户接线与验收

本次新增群晖 SSO Server → Supabase Auth 登录接线。代码与本地测试不等同于真实服务部署；真实 issuer、Supabase 项目、OIDC 应用注册与同源 HTTPS 尚未提供，`Shane` 的完整登录链路未验证。

最新测试、三端构建产物和未验收边界见 [本地验收记录](identity-validation.md)。

## 实现归属

| 位置 | 职责 |
| --- | --- |
| `../shared_packages/app_identity` | 公共身份状态、Supabase 适配器、安全存储与 Web Cookie 适配器 |
| `lib/features/identity` | 公开配置、恢复/登录/取消/退出、数据作用域切换 |
| `lib/ui/shared/account_screen.dart` | 三端共用的整页账户界面 |
| `server/identity_web` | Web 同源 HttpOnly Cookie 服务；使用官方 Supabase JS SDK |
| `scripts/identity` | TLS 严格的兼容性检查及显式提供方注册工具 |
| Android manifest、Windows runner / installer | 本机浏览器回调与有界窗口转交 |

本机使用 Supabase Flutter 2.17.2 的 PKCE 和加密持久化，安全存储兼容当前工程的 flutter_secure_storage 9.2.4。会话和 PKCE 分应用、部署命名空间，不使用整个安全存储的 deleteAll。取消登录有期限与持久化标记；退出分别呈现本机清理与服务端撤销未确认。

Web 使用同源 BFF；浏览器只保留公开用户提示及离线退出标记，不保存 access/refresh token。提示仅可用于离线本机展示，不能授权远端请求。离线退出不自动恢复 Cookie 会话，重新登录前补做服务端退出。参见 [Web 会话服务](identity-web-session.md)。

取消登录不会关闭系统浏览器。退出应用会话不等于退出 NAS 浏览器会话，也不会退出其他设备。群晖已有 SSO Cookie 时，再登录可能无需再次填写密码。

旧 Android 全局接受任意 HTTPS 证书的代码已移除；资源传输也使用正常证书校验。Android 关闭系统自动备份，避免会话密文与设备密钥分离后错误恢复；既有配置导入导出仍可用。

## 个人数据边界

个人数据按部署和 Supabase 用户 UUID 生成哈希命名空间。喜欢、浏览、搜索、活动、对话/选择、AI 回答偏好、国庆清单/票数缓存及推荐记录隔离。旧数据只属于访客，不复制给第一个登录者。AI compaction 和诊断账本也隔离。

切换前停止 AI/听写/TTS，等待旧写入完成。切换期间移除旧界面、导航与草稿，失败保持遮挡并提供重试；迟到结果不能写进新账户。

主题、语言、资料源、AI 服务凭据和更新 WebDAV 仍是设备应用配置。本次没有实现三端业务数据同步；账户业务数据仍在本机。原 DAV 设备票箱继续供访客使用，登录账户不复用该匿名协议，避免把设备票数冒充账户票数。

## 真实配置与验收

应用仅接收 Supabase HTTPS 根地址、publishable/anon 公钥、`custom:synology` 和 Web 回调。应用不接收群晖密码、OIDC client secret 或 Supabase 管理密钥。

普通账户页不显示部署表单，仅提供登录、取消、退出及必要的重试。公开配置由部署维护：Android / Windows 从发布构建的外置运行文件注入，Web 从同源 `/api/identity/configuration` 获取。配置未就绪时明确显示服务不可用，点击登录会重新检查配置，不将技术参数填写交给用户。配置完成后的流程是点击登录 → 群晖登录页（用户名、密码及账号要求的验证）→ 自动返回应用；验证步骤和页面样式以实际群晖策略为准。

使用 [部署指南](identity-deployment.md) 的私有文件示例。Well-known URL 从 SSO Server 复制，不能从 WebDAV 地址或 DSM API 登录结果推断。群晖登记 Supabase `/auth/v1/callback`；Supabase 另登记 Web `/auth/callback` 和本机 `org.dpdns.cznas.boardgame://auth/callback`。

私有配置留在仓库外的受限文件中，通过文件路径提供，不能放入 Flutter 资源、公开构建参数或 Git。缺少管理连接时不猜测提供方或虚构账号。

本地测试覆盖取消、超时、迟到事件、退出清理失败、数据切换故障、账户账本、Cookie/CSRF、PKCE、刷新、过期、重启与撤销重试，不生成渲染图。真实验收仍需正确/错误密码、真实回调、冷启动、过期刷新、断网退出、两个账户、NAS 禁用与撤销延迟。当前不能报告 `Shane` 登录成功或失败。

回滚先停 Web 服务，恢复旧客户端及兼容 BFF 数据快照/密钥。旧客户端继续读取访客数据，新账户命名空间保留，不删除聊天或个人数据。撤销新提供方须使用服务端正式流程，单独处理已签发会话；删本机配置不等于远端全部退出。
