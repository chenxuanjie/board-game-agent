# 认证方案保存点

当前工作分支为 `codex/synology-direct-auth`，主项目与公共 `app_identity` 同名。它直接访问 DSM，不部署应用会话服务。

上一个会话服务方案另外保留：主项目 `codex/synology-auth` 的 `e4e5955`，公共 `app_identity` 同名分支的 `56fe682`。原 Node 服务与三端 Cookie/应用令牌实现只在保存分支保留，不在直连分支并存使用。

2026-10-05 按用户要求，在改用 `SYNO.API.Auth` 前保存 Supabase / 群晖 OIDC 实现。这里保存的是代码，不代表远端 SSO 已部署或真实登录已通过。

主项目保存分支：`codex/supabase-identity-archive`，提交 `ee490d7`。新实现从该提交创建 `codex/synology-auth`，不修改保存分支。

公共包均为独立 Git 仓库，保存分支为 `codex/pre-syno-auth-20261005`：

| 公共包 | 保存提交 |
| --- | --- |
| app_identity | c4bddad |
| app_about | 5f594f9 |
| app_ai_client | 35acce5 |
| flutter_release_publisher | c507a50 |
| remote_update | afcac8e |
| webdav_settings | 3e86c42 |

各保存提交标题均为 `chore(包名): 保存切换群晖认证前的公共包实现`。运行时凭据、签名材料、构建目录和会话数据库不进入 Git。

恢复旧认证方案时，主项目切回保存分支，`app_identity` 切回自己的保存分支，再执行 `flutter pub get`。其余公共包保留在表中提交即可。两套认证使用独立配置键与会话命名空间，不自动迁移登录凭据或把群晖账号名匹配成旧 Supabase 用户。

保存前执行了主项目与认证包的 diff 检查；本机 Flutter 测试启动遭遇 localhost WebSocket 代理错误，未据此标记验证通过。已有验证记录见 `identity-validation.md`；切换后将重新验证新认证链路。

后续排查将 localhost 代理绕过限制在测试进程内，原保存点账号与数据隔离回归 39 项通过。新 Auth 方案验证结果见当前分支的 `identity-validation.md`。
