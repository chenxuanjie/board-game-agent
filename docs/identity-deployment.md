# 群晖 Auth 服务部署

代码已接入，但需把会话服务部署到实际 HTTPS 应用域名后，三端才能正式使用。
Web 与 `/api/identity/` 必须同源；Android/Windows 连接同一服务。无需注册 Supabase 或 SSO 应用。

1. 准备有有效 TLS 证书的应用域名与 Node 24.19+（24.x）运行环境。NAS 的 DSM HTTPS 地址为 `https://cznas.dpdns.org:5001`；5006 是 WebDAV，不能作为登录 API。
2. 将 `server/identity_web` 部署到私有服务目录。复制 `.env.example` 到 Web 根目录外的私有文件，由服务账号独占读取。
3. 填入 `PUBLIC_WEB_ORIGIN`（实际应用 HTTPS 域名，不带末尾 `/`）和 `SYNOLOGY_ORIGIN`。固定 `NAS_INSTANCE_ID` 和 32 字节密钥，更新时保持不变。示例生成命令：

   ```sh
   node -e "console.log(require('node:crypto').randomBytes(24).toString('base64url'))"
   node -e "console.log(require('node:crypto').randomBytes(32).toString('base64'))"
   ```

4. 设置全新 `SESSION_DB_PATH`，限制目录权限，不放在 Web 根目录、Git、公共 WebDAV 或旧 Supabase 会话库中。密码不写入这份配置。
5. 运行 `node --env-file=/private/path/identity.env src/main.js`。服务仅监听 `127.0.0.1:8787`。可参考 `deploy/board-identity.service.example`；群晖 Container Manager 部署时需持久化私有数据库并配置进程环境。
6. 参考 `deploy/nginx.conf.example` 把同域 `/api/identity/` 转到服务。替换固定 Host，禁用该路径的请求正文、Cookie、Authorization、URL/异常追踪日志；配置代理限流。NAS/中间代理也不能记录带 `_sid` 的完整 URI。不要开放 8787 到公网。
7. 浏览器访问 HTTPS Web；原生构建增加 `--dart-define=IDENTITY_SERVICE_URL=https://实际应用域名`。应用自动读取公开连接元数据。公开地址不能包含密码、NAS SID 或密钥，原生首次构建不能留空此地址。
8. 按 [验收记录](identity-validation.md) 检查三端真实登录、验证码、恢复、退出与账号隔离，再发布安装包。

## 运维边界

默认会话闲置 30 分钟、绝对 24 小时；凭据登录最多同账号每 15 分钟 5 次失败，正确登录重置计数。
NAS 会话加密落盘，应用凭据只存随机令牌哈希。退出先删除应用会话，再撤销 NAS；失败进入加密重试队列，最多 12 次/24 小时。
密码不持久化，因此过期后必须重新输入，不会静默刷新群晖密码登录。不同设备使用独立会话，本机退出不代表退出全部设备。
服务仅支持单进程单数据库；不应启动多个副本。异常断电可能留下 `.lockfile`，确认旧进程已停止后由管理员移除该文件再重启；不得运行时强行清除锁。
保持 NAS 标识、服务域名与密钥稳定；变更需明确迁移/退出计划。数据库与密钥分开备份，丢失密钥会使原会话不可恢复。

当前没有在 NAS 上部署此服务，也没有替用户创建域名/容器或修改 DSM 权限。
本机 `http://127.0.0.1:8081` 预览不能据此当成正式 HTTPS 登录已接通。
