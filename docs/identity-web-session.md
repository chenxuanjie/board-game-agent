# Web Cookie 会话服务

实现目录为 `server/identity_web/`，Node 原生 HTTP + SQLite 持久化，直接使用 `@supabase/supabase-js` **2.117.2**。浏览器持有不透明 SID；Supabase access/refresh token、NAS provider token、PKCE verifier 和 CSRF 状态只保存于服务器的 AES-256-GCM 加密记录。没有自研 OIDC/JWKS/JWT 验证器，也没有浏览器 JWT / localStorage 身份回退。

**真实 Supabase 项目、NAS OIDC issuer 和注册配置尚未提供，实际登录与远端撤销未验证。** 部署操作员需要先在 Supabase 管理端确认 `custom:synology` 可用，配置 NAS 的 issuer、client ID/secret 与 Supabase 给出的 provider callback，并在 Supabase 的 Redirect URLs 中精确登记 Web callback。NAS client secret 只进入 Supabase 管理端；本服务与客户端不收集这类凭据。不得把测试网关通过当作真实 OIDC 已验证。

## 客户端固定协议

全部路径位于 **PUBLIC_WEB_ORIGIN 指定的同一个 HTTPS origin**，浏览器请求使用 `credentials: 'include'`。无 CORS 开放，不接受客户端 Authorization/JWT。Host 必须与该 origin 完全一致；服务不信任 X-Forwarded-*。Origin 只允许精确的配置 origin，`same-site` 的兄弟域不算同源。

| 方法 / 路径 | 成功响应 | 行为 |
| --- | --- | --- |
| GET `/api/identity/configuration` | `{ "supabaseUrl": "…", "publishableKey": "…", "providerId": "custom:synology", "webCallback": "https://…/auth/callback" }` | 服务器公开配置权威来源，publishableKey 可为 publishable key 或登记过的旧式 anon API key；不会返回加密 key、service-role key 或 NAS secret |
| GET `/api/identity/session` | `{ "user": { "id": "…", "email": "…", "displayName": "…" } }` 或 `{ "user": null }` | email / displayName 可为 null；已登录会话每次由 SDK `getUser(accessToken)` 向 Supabase 验证，SDK 会话缓存中的 user 不作为身份证明 |
| GET `/api/identity/csrf` | **`{ "csrfToken": "43-character-base64url" }`** | 创建匿名会话（如果需要）；token 绑定当前 SID |
| POST `/api/identity/sign-in` | `{ "authorizationUrl": "https://registered-supabase/auth/v1/authorize?…" }` | 空 body 或 JSON `{}`；固定 provider，不接受 provider / redirect / Supabase URL 参数；创建 SDK PKCE 流程 |
| GET `/auth/callback?code=…` | HTTP **303**，`Location: /` | SDK `exchangeCodeForSession` + `getUser`，成功后更换 SID 与 CSRF；失败为清理后的 JSON 错误 |
| POST `/api/identity/sign-out` | `{ "user": null }` | 空 body 或 JSON `{}`；先销毁 BFF 会话并清 Cookie，再用 SDK `signOut({scope:'local'})` 撤销当前 Supabase 会话 |
| GET / PUT `/api/identity/userdata` | 固定上游的 JSON | 可选，未配置时 404；每次验证身份；PUT 为 JSON 对象，最大 64 KiB |

**Cookie 的准确属性：** `__Host-bga_sid=<32 random bytes, base64url>; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=<remaining absolute lifetime>`。没有 Domain。Path 必须为 `/`，因为它同时覆盖 `/api/identity/*` 和 `/auth/callback`。清理使用同名、同 Path、同安全属性、`Max-Age=0`。SID 的 SHA-256 作为 SQLite 索引，Cookie 从不包含用户身份或 token。

所有 POST / PUT 必须同时发送精确的 **`Origin: PUBLIC_WEB_ORIGIN`** 与 **`X-CSRF-Token: <GET /csrf 的 csrfToken>`**；浏览器自动提供 Origin。缺失、串用、错误 Origin 或 CSRF 为 403。sign-in 与 callback 都会轮换 SID / CSRF，因此在轮换后、下一次 mutation 前重新 GET `/csrf`。GET `/session` 不返回 CSRF 或任何 token。无额外 query 参数或动态 redirect。

displayName 从 SDK getUser 验证返回的 user_metadata 中依次选择 `full_name`、`name`、`display_name`、`preferred_username`、`username`、`nickname`。跳过非字符串和清理后为空的值，移除控制字符、限制 200 字符并 trim；都不可用时为 null。不会返回其余 metadata，也不会使用缓存 metadata 代替实时验证结果。

客户端启动顺序：从同源 `/configuration` 取得公开配置，检查固定 provider、当前页面 origin 与 callback 一致，再初始化 CookieIdentityGateway 并读取 `/session`。普通账户页不提供部署参数表单，不能覆盖服务器配置或构造另一套 browser token 登录。登录前取 `/csrf`，POST 空 sign-in，浏览器导航至返回的 authorizationUrl；成功 callback 后重新获取 session 与 csrf。

POST sign-in 在产生 authorizationUrl **之前**就销毁旧 BFF 会话，创建新匿名 SID；取消流程后 session 为 null，旧账号不能恢复。旧 SID 上排队的请求重读 SQLite；失效请求不会重建旧会话，也不会用清 Cookie 响应覆盖新 SID。客户端同样要用会话 generation / request gate 丢弃登录、退出、切换前发起的旧请求结果。

退出时客户端先保存本地“待远程退出”提示并清本地身份。在离线、超时或 503 后，此提示应阻止 `/session` 的自动身份恢复，直至远程退出重试完成；显式重新 sign-in 可进入新的身份流程。若退出请求根本未到服务器，旧 Cookie 仍可能有效，客户端不能仅凭本地 UI 清理宣称完成撤销。重试时先 GET `/csrf`，再 POST `/sign-out`。

远端撤销失败时 HTTP **503** 返回 `{ "user": null, "error": "revocation_pending" }`，BFF Cookie 已清除、旧 SID 已失效。加密 SQLite outbox 保存最后可用 SDK 会话（SDK signOut 自行清空 storage 也不会丢失重试凭据）。每 5 秒检查到期任务，最多 12 次尝试，指数退避至最多 1 小时，24 小时后清除。后续客户端 sign-out 会保证当前 BFF Cookie 已清除；历史远端撤销由服务器 outbox 独立重试。Supabase 退出不会立即废止已发行的 access JWT，它按其 exp 到期；NAS SSO 是否仍保留登录由 NAS 策略决定。

一般失败为 `{ "error": "stable_code" }`。403 可重新取 csrf 后由用户重试；401 身份失效，session 读取会收敛为 200 `{user:null}`；502/503/504 表示服务或网络问题，客户端不能将它们当作已验证的未登录状态或启动其他认证方案。SDK 原始错误、code、Cookie、token、上游正文都不进入返回错误或服务日志。所有响应 `Cache-Control: no-store`。

## 私有配置与部署前提

需要 **Node 24 LTS >=24.19.0 且 <25**，包含 `node:sqlite` 和 WebCrypto；npm 仅安装此目录的锁定依赖。没有全局安装、编译产物或本地 C/C++ SQLite addon。使用单个进程 / worker；SQLite 文件必须放在本机持久卷，不放 NFS/SMB/WebDAV。服务只监听 `127.0.0.1:8787`，由同机 HTTPS 反向代理转发。

复制 `server/identity_web/.env.example` 到 web root / 仓库之外的私有 env 文件（Linux 权限 0600，目录 0700，Windows 限定服务账号 ACL）。该示例全是占位值，无法直接启动。填入：

- `PUBLIC_WEB_ORIGIN`：canonical HTTPS origin，不含末尾 `/`、路径、query 或 credentials。
- `SUPABASE_URL` 与 `REGISTERED_SUPABASE_URL`：操作员审核过的相同 HTTPS origin；不接受尾 `/` 或额外路径。
- `SUPABASE_PUBLISHABLE_KEY`：所登记项目的 `sb_publishable_…` key，或 self-hosted 常见的旧式 JWT API key（payload 必须为对象且 `role` 严格等于 `anon`）；不能是 secret / service-role / authenticated key。为兼容客户端，环境变量名及 `/configuration` 的 `publishableKey` 字段名保持一致。`REGISTERED_SUPABASE_KEY_SHA256` 对两种格式都必须匹配准确字节的 lowercase SHA-256 hex。
- `REGISTERED_CALLBACK_URL`：必须准确等于 `${PUBLIC_WEB_ORIGIN}/auth/callback`，且已加入 Supabase Redirect URLs；不要 wildcard。
- `SESSION_ENCRYPTION_KEY`：私有的随机 32 字节 key，标准 base64 编码；可用 Node `crypto.randomBytes(32)` 在操作员私有环境中生成，不能提交或送入前端。
- `SESSION_DB_PATH`：可写的私有绝对路径；数据库、WAL、SHM、lockfile 与备份都限制服务账号权限。

配置不完整、URL / callback / key fingerprint 与 registration pins 不一致，进程启动失败，**不提供认证端点**。这些 pins 是经操作员核实的注册记录，不是向 Supabase 管理 API 探测配置的凭据；相等本身不能证明 NAS 或 Supabase 实际已登记，所以部署验收仍要做真实流程。客户端不能提交或修改 pins。本服务不接收 NAS admin / OIDC client secret。

旧式 anon API key 属于[官方公开 API key 类型](https://supabase.com/docs/guides/getting-started/api-keys)，虽然格式是 JWT，但不是用户 access token。BFF 仅在启动时解码私有 env 中、操作员登记并由 SHA-256 pin 约束的 key，检查其公开角色类型；这不是 JWT 签名验证，不验证 OIDC 或用户身份。实际凭据验证仍交给 Supabase SDK / Auth。拒绝畸形 JWT、非 anon 角色与所有 `sb_secret_…`，即使其 fingerprint 恰好已登记也不发布到 `/configuration`。

默认 authenticated idle 30 分钟、absolute 24 小时；分别限定 60–3600 秒与 300–604800 秒。匿名会话最多 10 分钟（不超过 absolute）；PKCE 等待最多 5 分钟。有效访问更新 idle，不能推迟 absolute。服务器过期控制权威，Cookie Max-Age 只作浏览器清理。刷新由 SDK 执行，接近到期时调用 `refreshSession`，SDK storage 更新立即加密持久化，后续 getUser / userdata 失败也不会丢失已轮换的 refresh token。

认证 callback 签发的 Cookie Max-Age 按 **absolute** 期限计算，默认为 **86400 秒**，不按 30 分钟 idle 计算。成功 GET `/session` 只更新 SQLite `seen`，既不修改 `expires`，也不续发 Set-Cookie。因此持续使用可以跨过最初的 idle 截止点，但始终无法延长 absolute；闲置到 idle 时，即使浏览器 Cookie 尚未到期，数据库也拒绝身份。缺失的旧 SID 返回 null 且不发送 Set-Cookie，避免旧 session 响应覆盖轮换后的 Cookie。

HTTP 总时限默认 10 秒，范围 1–30 秒；最多 128 个并发请求，单个 SID 串行处理并且排队也算入时限；每个 SDK 操作最多 6 个上游请求（包括 SDK 自身重试）。SDK 请求与正文读取受 AbortSignal 限制；迟到的 SDK storage 写入被禁用，过期 / 失效 SID 不能持久化。请求正文 64 KiB，上游 Auth 正文 1 MiB、userdata 64 KiB，HTTP headers 16 KiB。sessions + revocations 总数由 MAX_SESSIONS 限定，默认 10000，满时拒绝新增会话；反向代理还应按 IP 限流。

安装 / 检查 / 启动（在 `server/identity_web/` 目录）：

```sh
npm ci --ignore-scripts
npm run check
npm test
# Node 自带 env-file 支持；或者由 systemd EnvironmentFile 注入。
node --env-file=/etc/board-identity/private.env src/main.js
```

没有 build 步骤：源码 ESM 直接执行。示例 `deploy/board-identity.service.example` 使用隔离服务账号与持久化 StateDirectory；`deploy/nginx.conf.example` 必须并入承载 Flutter Web 的 **同一 HTTPS vhost**。替换固定 Host，开放 `/api/identity/` 与准确的 `/auth/callback`，保留请求 URI、Cookie、Origin、X-CSRF-Token，不重写 Cookie path。若 origin 含非默认端口，Host 也必须含该端口。不要让 SPA fallback 吞掉这些路由。代理、CDN、监控与访问追踪也必须禁用 callback query、身份 header / 正文日志和缓存。

SQLite 使用 WAL、FULL 同步与 1 秒 busy timeout，AES-GCM 每次写入使用新随机 nonce，AAD 绑定版本与 SID hash，篡改 / 错 key 的记录不能登录。启动用独占 `.lockfile` 防止多进程 refresh races；正常退出删除 lockfile。进程崩溃后，需要确认旧进程完全停止才移除 stale lockfile。现阶段不支持多副本；如需扩容，应整体替换持久化与跨进程互斥方案，而不是启动第二个共享 SQLite worker。

备份使用 SQLite 一致性快照并保存私有 key；不要仅复制运行中的主 DB 而忽略 WAL。变更加密 key 会使已有会话无法解密（相当于整体退出），不自动迁移旧 key。回滚时停服务，恢复此前代码 / lockfile 的依赖与兼容数据库快照，保持原 key；数据库可能含旧会话时，应通过清库并要求重新登录实现明确撤销边界。

## 可选 userdata 代理

同时设置 `USERDATA_UPSTREAM_URL` 与完全相同的 `REGISTERED_USERDATA_UPSTREAM_URL` 才开启。仅转发至该固定 HTTPS endpoint，禁止动态 URL / path / query / redirect。GET 与 PUT 都由 SDK 验证当前用户，然后服务器将 Supabase access token 放入 Authorization；浏览器只收到业务 JSON，不收到 token，也不透传上游 headers。

上游必须验证 Supabase 身份并通过 JWT sub / RLS 隔离用户，不能仅相信 `X-Identity-User` 提示 header。本服务不替代上游授权。上线前核实该固定服务可以接收 Supabase JWT，且响应模型不包含 auth 字段；若协议不一致，保持代理关闭。响应有 auth / secret 字段、当前身份凭据字符串或 JWT 形式字符串时拒绝返回。只有 GET / PUT；NAS WebDAV 任意路径代理、第三方 token 交换均不在此服务范围。

## 官方复用与依赖审查

2026-10-04 检查官方 repository release / npm metadata，锁定 [Supabase JS v2.117.2（2026-09-25）](https://github.com/supabase/supabase-js/releases/tag/v2.117.2)，MIT license，官方仍持续发布维护；对应 auth-js、functions-js、postgrest-js、realtime-js、storage-js 均为 2.117.2。完整间接依赖由 `package-lock.json` 固定并带 registry integrity，执行 `npm ci`，升级时重新审查 release、安全公告与 HTTP 回归，不跟随浮动 latest。

直接复用 SDK 的 [custom OAuth/OIDC provider](https://supabase.com/docs/guides/auth/custom-oauth-providers)、[PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow)、[exchangeCodeForSession](https://supabase.com/docs/reference/javascript/auth-exchangecodeforsession)、[getUser](https://supabase.com/docs/reference/javascript/auth-getuser)、[refreshSession](https://supabase.com/docs/reference/javascript/auth-refreshsession) 与 [signOut](https://supabase.com/docs/reference/javascript/auth-signout)。实现可追溯至 [v2.117.2 GoTrueClient.ts](https://github.com/supabase/supabase-js/blob/v2.117.2/packages/core/auth-js/src/GoTrueClient.ts)、[PKCE storage helpers](https://github.com/supabase/supabase-js/blob/v2.117.2/packages/core/auth-js/src/lib/helpers.ts)、[SupabaseClient.ts](https://github.com/supabase/supabase-js/blob/v2.117.2/packages/core/supabase-js/src/SupabaseClient.ts)。SDK 直接运行于 Node，不在 Flutter 重写 OIDC；NAS 发现文档、JWKS、ID token 验证完全交给 Supabase Auth。SQLite 使用 [Node 原生 node:sqlite](https://nodejs.org/docs/latest-v24.x/api/sqlite.html)，AES-GCM 使用原生 crypto。

发布前运行 `npm audit --omit=dev` 并查官方 advisories；锁定版本不能保证以后没有漏洞。SDK 错误响应先脱敏，再交还 SDK；不开 auth debug / realtime tracing，服务日志只有状态码与固定错误标识。

本次干净 `npm ci --ignore-scripts --no-fund`、`npm ls --all` 与 `npm audit --omit=dev` 已核实 lockfile：9 个实际依赖包，SDK 家族均为 2.117.2，`@supabase/phoenix` 0.4.5、`tslib` 2.8.1、`iceberg-js` 0.8.1；2026-10-04 audit 报告 0 项已知漏洞。可选 `@opentelemetry/api` peer 未安装，因为此服务不使用 SDK tracing 子路径。`.npmrc` 强制 engine 与 exact direct versions，启动入口也拒绝不满足 Node 24.19+ / <25 的运行时。

## 验收与已知限制

`test/http.test.js` 用真实 Supabase JS SDK，注入具有 PKCE challenge 校验、一次性 code 与 refresh token 的假 HTTP gateway，监听 loopback 服务。Cookie jar 由测试手动管理，仅用于测试 HTTP；生产仍强制 HTTPS + Secure。

自动测试覆盖：配置 pins 不符拒绝、公开 configuration / session / csrf 的准确 contract、Origin / CSRF / Host、Cookie 属性、跨用户隔离与 PKCE code 串用、加密 PKCE 经重启恢复、callback 单次兑换及 rotation、登录取消时旧身份失效、idle / absolute / PKCE expiry、SDK getUser 真正用于验证、刷新并发去重与持久化（包括验证失败后）、退出失败的加密撤销重试、上游超时、固定 userdata 代理与 token 泄漏拒绝、数据库独占与密文篡改。语法检查与 HTTP 测试通过；这不证明真实配置或远端兼容性。

本次 Synology / legacy anon 兼容修订在 Node v24.19.0 上运行 `npm run check` 与 `npm test`：**21 项测试通过，0 失败、0 跳过**，其中新增 6 项测试。新增覆盖包含 10 组显示名优先级 / 非字符串 / 空白 / 控制字符 / 长度限制场景、跨浏览器显示名隔离、24 个高权限或畸形 key 拒绝场景、3 个 registration pin / 项目不匹配场景，以及旧式 anon key 的 configuration → SDK PKCE → getUser → logout 本地 HTTP 链路。假网关 JWT 签名仅为测试数据，未验证真实项目。

Cookie 期限复核补充 3 项回归：测试浏览器按响应的 Max-Age 决定是否发送 Cookie；持续访问跨越初始 idle、恰在 absolute 时停止认证（并额外重放 SID 验证数据库上限）；未过 absolute 的 Cookie 在 idle 边界被拒；旧 SID 响应与并发正常 session 读取均不续发或替换新的 Cookie。复核后的总数为 **24 项通过，0 失败、0 跳过**。Cookie 本来已按 absolute 签发，本次保留该行为，补充明确注释与回归证据。

真实验收尚需：同源 HTTPS 下完成 NAS → Supabase → callback → session；两个浏览器同时登录不同用户；取消再次登录；跨站表单 / 兄弟域 Origin 被拒；按默认时限验证 idle / absolute 与 refresh；断网退出后客户端提示不自动恢复；服务重启与远端撤销重试；userdata RLS 隔离及越权请求失败；在浏览器存储、网络返回与服务 / 代理日志中检查没有 auth secrets。Web 窄屏 / 宽屏与 Dart 集成由主 agent 验证。本服务不改变 Android / Windows 身份实现，三端 UI 与真实 NAS 登录尚未验收。

## 真实验证阻塞项（未部署）

- **Supabase 项目未知**：缺少经操作员确认的项目 URL、publishable 或旧式 anon key fingerprint、已登记的精确 Web callback，以及该实例中启用 `custom:synology` 的证据。self-hosted Supabase Auth 的实际版本与 custom OIDC 支持也未知；成熟 JS SDK 不能给旧 Auth 服务补上 provider 能力，必须先按 [官方 self-hosted custom provider 文档](https://supabase.com/docs/guides/self-hosting/self-hosted-custom-oauth-providers)确认服务端能力。
- **NAS issuer / OIDC 注册未知**：缺少真实 discovery issuer、provider callback 登记、用户 claims 映射和 NAS PKCE 兼容性证据。由操作员在 Supabase / NAS 管理端配置并现场验收，不向本项目收集管理凭据或 OIDC client secret。
- **实际运行平台未知**：本次只在 Windows x64 bundled **Node v24.19.0** 执行测试。不能假设 DSM 的 Node 套件足够新。按 [Node v24.19.0 官方支持表](https://github.com/nodejs/node/blob/v24.19.0/BUILDING.md)，Linux x64 / arm64 的 Tier 1 基线为 kernel >=4.18、glibc >=2.28；armv7 是 Experimental。需核实 NAS 型号、CPU、kernel、libc、Node 与本机 SQLite 持久卷权限；容器共享宿主 kernel，不能靠更换镜像消除旧 kernel 限制。若 NAS 不满足基线，在符合要求的 Linux 主机或 VM 运行 BFF，经同源 HTTPS 代理接入；不降低 Node 或 TLS 要求。
- **同源 HTTPS 与网络未知**：尚未验证真实 PUBLIC_WEB_ORIGIN、受信任 TLS 证书、Host 转发、Cookie round trip、Supabase / NAS 网络可达性及日志脱敏。未提供任何 TLS bypass、`NODE_TLS_REJECT_UNAUTHORIZED=0`、HTTP callback 或非 Secure Cookie 开关。
- **业务数据授权未知**：可选 userdata endpoint / RLS 模型未确认；保持代理关闭，直至用户隔离、返回 JSON 模型与固定上游登记完成。

以上阻塞的是**真实部署与联调验收**，不是本地 HTTP 测试。未执行部署、全局安装或 Git 提交；不得将本服务标记为已在 NAS / Supabase 上线验证。
