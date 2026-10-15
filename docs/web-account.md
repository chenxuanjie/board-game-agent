# Web 账号接入

2026-10-16。当前实现范围：Web 群晖账号登录、按需 OTP、服务器验证后的稳定身份、刷新恢复、退出、取消、账号本机数据隔离，以及 [只读挂载资料访问](web-library.md)。**尚未接入 Web 私人云同步、公共统计写入或评论**；登录不代表数据已同步或所有文件均可读取。Android/Windows 保留原生直连及原安全存储。

## 结构与复用

浏览器 → 同源 `/api/account/` → Nginx → `web-account:8000` → 固定配置的 DSM HTTPS API。网关不开放宿主机端口，没有任意 URL 代理、文件写入或 NAS 目录初始化接口；新增只读资料校验与内部文件转发见专项文档。前端在 `web_account_gateway.dart` 实现现有 `IdentityGateway`，继续复用 `app_identity` 的 `IdentityController`、已验证身份状态与 `AccountService` 的账号作用域，不修改共享包。

共享 `SynologyIdentityGateway` 明确拒绝 Web，依赖原生安全存储，不能直接用于浏览器；Python 网关也不能导入 Flutter 包。因此仅将它的 API 发现 → Auth v6 → FileStation.Info v2 验证 UID 流程适配到 HTTPX，HTTP/ASGI、Cookie 和路由复用 Starlette，不实现第二套用户数据库。协议依据：[DSM 官方登录流程](https://kb.synology.com/en-global/DG/DSM_Login_Web_API_Guide/2)。

身份 ID 仍为 SHA-256(`synology-direct-v1|<canonical origin>|<DSM UID>`)，账号名只作显示。必须将 `SYNOLOGY_IDENTITY_ORIGIN` 配成原生端既有 canonical origin，才能保持身份相同；浏览器本机数据和原生设备本机数据不会因此自动复制，云同步仍是独立能力。

## 请求与会话

| 接口 | 行为 |
| --- | --- |
| GET `/api/account/config` | 返回受信任登录地址与 canonical origin，不包含凭据 |
| GET `/api/account/session` | 建立匿名 Cookie 或向 DSM 验证现有会话；返回已验证用户或 null |
| POST `/api/account/login` | 只接受 account/password/可选 otp；登录并验证 UID 后才返回用户 |
| POST `/api/account/logout` | 先使站点会话失效、取消在途登录，再尽力撤销 DSM 会话 |

所有请求要求 `X-Board-Game-Request: 1`；存在 Origin 时必须与配置完全一致，拒绝 cross-site，不开放 CORS。浏览器密码仅放 POST 正文，服务端 DSM 请求也使用 POST；不跟随上游重定向，TLS 校验开启。输入最大 8 KiB，上游响应最大 64 KiB；单次上游请求 8 秒、登录总预算 18 秒、验证 12 秒，退出撤销等待最多 2 秒。登录按 IP 和账号分别限制每分钟 10 次，最多保留 4096 个限流键；失败不自动重试。

Cookie 是 256 位随机站点标识，HttpOnly、Secure、SameSite=Strict、Path=/，不包含 NAS SID/SynoToken/密码。SID 与 SynoToken 仅存服务端内存；最多 1024 个会话，空闲 30 分钟、绝对 8 小时过期，单 worker。网关重启后用户需重新登录，不使用数据库或把会话写入镜像。浏览器不保存密码或登录历史；只有退出失败时存一个不含身份和凭据的布尔标记，刷新后先补退出，禁止恢复旧登录。

取消、退出和过期都会递增服务端会话版本；晚到登录只能撤销自己的候选 NAS 会话，不能重新发布身份。多标签共用站点 Cookie，其他标签下一次会话验证会发现退出。客户端初始化、返回前台和前台每 60 秒继续使用现有账号验证调度；定时器不保证后台标签准时执行。登录状态不代表资料访问资格，Web 不生成或保存 WebDAV 密码。

## 部署

复制 `packaging/docker/.env.example` 为 `.env` 并设置：

```dotenv
WEB_PORT=8887
SYNOLOGY_ORIGIN=https://nas.example:5001
SYNOLOGY_IDENTITY_ORIGIN=https://nas.example:5001
WEB_PUBLIC_ORIGIN=https://board-games.example
WEB_ALLOW_INSECURE_HTTP=false
```

`SYNOLOGY_ORIGIN` 是容器可访问、证书有效的 DSM 地址，不能填容器自身 localhost；canonical origin 可与其不同，但应代表同一台 NAS。`WEB_PUBLIC_ORIGIN` 必须是浏览器地址栏中的完整 origin（包含非默认端口），网站入口应由 NAS HTTPS 反向代理转发到 8887。只在明确的本机/内网 HTTP 测试中将 `WEB_ALLOW_INSECURE_HTTP=true`，同时把 public origin 改为实际 HTTP 地址；这种模式会取消 Cookie 的 Secure 属性。自签 CA 可通过只读挂载 CA 文件并设置 `DSM_CA_FILE` 加入信任，不提供关闭证书验证的开关。

使用 `docker compose up -d --build` 启动两个服务。网关有独立的 `Dockerfile.dockerignore`，构建上下文只纳入 app.py、library.py、依赖清单与 Docker 配置，不发送资料库、发布包、凭据或本机缓存。另需设置资料挂载的两个路径，见 [部署说明](docker-deployment.md)。原始 `flutter run` 或纯静态预览没有 `/api/account/` 和 `/library/`，不能当成已部署登录或资料访问。没有修改 NAS 权限、创建目录或写入真实账号测试数据。现有静态 `/healthz` 仍只代表 Nginx 存活，不代表 DSM 可达。

## 依赖与验收

| 组件 | 版本/许可证 | 使用范围及升级检查 |
| --- | --- | --- |
| Starlette | 1.8.0 / BSD-3-Clause | ASGI 路由、Cookie 和生命周期；检查请求解析与 Cookie 行为变化 |
| HTTPX | 0.28.1 / BSD-3-Clause | 固定 DSM 上游、TLS、连接池及流式响应限制；检查超时、证书与代理策略 |
| Uvicorn | 0.54.0 / BSD-3-Clause | ASGI 运行服务，关闭访问日志及代理头自动信任；维持单 worker |

来源：[Starlette](https://github.com/Kludex/starlette)、[HTTPX](https://github.com/encode/httpx)、[Uvicorn](https://github.com/Kludex/uvicorn)。新依赖只用于独立服务，不进入 Flutter。顶层版本固定在 requirements.txt；升级需重跑登录、退出竞态与输入边界测试。未完成外部漏洞扫描或真实 NAS 上线验收，不声称已通过生产安全审计。

服务端测试运行 `PYTHONPATH=<测试依赖目录> python -m unittest discover -s services/web_account/tests -v`；2026-10-16 资料接入后共 36 项通过（设置 `NGINX_BIN` 包含真实 Nginx 传输测试），使用 HTTPX 假 DSM，不访问实际 NAS。Flutter 全量 677 项通过，覆盖同源请求、OTP、恢复、退出补偿、晚到响应、320/1440 dp 大字体账户页、资料缓存/静默检查及旧原生行为；静态检查通过。此前 Chrome 浏览器测试停留在加载阶段后终止，未计作通过；不能将宿主机 widget 测试视为完整浏览器联调。本轮不构建、上传、启动 NAS 容器或测试真实凭据。真实 DSM（含 OTP）、HTTPS Cookie、NAS 反向代理及容器联调需部署后验收。

回滚使用前一版 Web 与 Compose 配置。网关无持久数据库，停止服务即可使站点会话失效；保留浏览器各账号业务数据，不清理 NAS 文件。同源资料源已作为后台替换接入，不新增前台切换提示；状态与检查界面本轮未调整。
