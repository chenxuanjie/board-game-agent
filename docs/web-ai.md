# Web AI 同源传输

2026-10-18。仅修改浏览器的 HTTP 传输路径；继续使用 app_ai_client 0.1.0、openai_dart 8.0.0 的模型发现、Chat Completions、Responses、流式解析、工具事件、重试和取消。原生端仍使用现有代理感知客户端。没有另建 AI 协议、会话库、计费账户或模型配置。

## 已确认的问题

通过 `https://cznas.pp.ua:18887/api/account/config` 的只读检查：请求 Origin 为 `https://cznas.pp.ua:18887` 时返回 403 accountDenied，声明旧 `http://cznas.pp.ua:8887` 时返回 200。反代已转到网关，失败来自网关仍只允许旧完整 origin。配套 YAML 与未来构建默认值已改为 HTTPS 18887，Secure Cookie 开启；容器映射仍是 8887:8080，TLS 由 NAS 反代终止。无需在容器内重复配置 TLS。

`https://www.loomex.lol/v1/models` 的浏览器式 OPTIONS 探测返回 403，没有 Access-Control-Allow-Origin，旧 Web 直接调用模式无法通过此预检。[MDN CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) 说明 Authorization 触发预检；不能仅在 Flutter 中设置请求头绕过服务商的浏览器限制。

## 数据流与复用

浏览器 SDK → `WebAiHttpClient` → 同源 `/api/ai/request` → Nginx → 现有 web-account 网关 → 配置允许的 HTTPS AI 提供商。

- `main.dart` 只为 kIsWeb 的普通及流式 SDK 客户端注入适配器。API 地址、Key、模型和问答设置继续使用既有配置；请求正文和协议事件不做重新映射。
- Dart 适配器转发原始取消信号和响应字节，不预收集完整流。主客户端由 BoardGameAiService 的释放回调关闭，流客户端仍由 SDK 关闭。
- Python 不能直接导入 Dart SDK；因此仅复用 HTTPX 的异步 TLS/连接池/手动流和 Starlette 的 StreamingResponse/断连生命周期，按 [HTTPX 官方异步流示例](https://www.python-httpx.org/async/) 与 [Starlette 响应接口](https://www.starlette.io/responses/) 关闭上游。没有复制 SSE 或 Responses 状态机。
- Nginx 对该路由关闭响应缓冲及缓存，使用 HTTP/1.1；断连关闭上游，途中失败不补造完成事件。NAS 外层反代也应保持流式转发，空闲超时至少覆盖网关的读取预算。

## 接口与边界

`X-BGA-AI-Target` 仅携带 SDK 的原始无凭据 HTTPS 目标地址，Key 只在认证请求头，均不写入访问日志或数据库。服务端要求同源自定义头和已有站点 Cookie；游客可继续使用自己的 Key，不借用 NAS 登录凭据。没有为所有用户配置公共 Key。

`AI_ALLOWED_ORIGINS` 是管理员配置的逗号分隔 HTTPS origin 允许列表，最多 16 项，包含非默认端口，不包含 `/v1` 路径。默认包括 api.openai.com、api.deepseek.com、www.loomex.lol、loomex.lol；其他服务商须由管理员添加。只允许 GET models，以及 POST chat/completions、responses、responses/compact，路径前缀沿用 SDK。拒绝自带凭据、查询串、目录穿越、非允许目标和重定向，不提供任意 URL 代理。

只转发 Authorization/api-key/x-api-key、JSON 类型、Accept 和 SDK 的 OpenAI 组织/项目/Beta/幂等头；不转发浏览器 Cookie、NAS SID/SynoToken、Origin 或代理身份。AI 与 DSM 使用不同 HTTPX 客户端，逐请求显式空 Cookie，响应不透传 Set-Cookie。错误正文最多 64 KiB，精确移除本次认证密钥；网络异常只返回固定错误信息，不能泄露异常原文。

请求最多 16 MiB、成功响应最多 64 MiB；每站点会话/IP 每分钟最多 60 次、总在途最多 8 个。连接 8 秒、写入 30 秒、读取空闲 60 秒、总预算 180 秒；流中超过预算会关闭不完整响应，不冒充成功。Nginx 读取超时 190 秒。允许列表和这些预算是部署边界，不等同于所有服务商都支持所有模型能力。

复用依赖保持锁定：openai_dart 8.0.0（MIT）、http 1.6.0（BSD-3-Clause）、HTTPX 0.28.1（BSD-3-Clause）、Starlette 1.8.0（BSD-3-Clause）。未新增依赖或复制其源码，保留现有升级策略；升级须复查流式首段、取消、模型列表、认证错误、Cookie 隔离和网关限额。没有做外部漏洞扫描或许可证法律审核。

## 配置生效与验收

现有 TAR 的账号网关已具备严格 origin 和 HTTPS Cookie 支持，因此登录地址修正可通过更新 YAML 并重新创建网关容器生效，随后刷新网页。仅重启沿用旧环境变量的容器不会应用新值。**AI 同源路由是本次源码新增，旧 TAR 不包含，须重新构建两个镜像并配套部署 Web 与 Nginx。** 没有在 NAS 上部署或使用真实 API Key 问答。

本地验证包括 HTTPS 非默认端口的站点 Cookie、模型列表、Chat/Responses/compact、原样 SSE、密钥不入 URL、取消信号、重定向/跨源/未允许目标拒绝、上游超时、429 和错误脱敏；真实 Nginx → ASGI → 模拟 AI 流首段在后续内容尚未生成时可到达。真实服务商付费问答、NAS 外层反代的首段延迟，以及完整浏览器联调尚未验收。

验证结果：网关 70 项中 68 项通过、2 项 Unix 权限元数据测试在 Windows 跳过；真实 Nginx 流式集成包含在通过项中。SDK/应用 AI 回归 47 项、离线 Docker/Compose 生成测试 15 项通过，Flutter 静态检查无问题。Docker 测试使用 FakeDocker，不构建或替换真实 TAR；本次没有构建或部署镜像。

回退时配套恢复主程序、Nginx 与网关源码；HTTPS origin 配置可以保留，不能为回退关闭 TLS 校验或放开全部来源。浏览器模型设置与 NAS 数据不迁移、不清理。
