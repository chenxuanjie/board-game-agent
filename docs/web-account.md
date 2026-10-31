> 历史接入/部署记录：当前客户端已替换账号、公开资料和业务协议，以 [阶段 2、3 记录](service-business.md) 为准；这里的旧 DSM/FileStation/Web 网关步骤不用于新服务。Web 部署仍暂缓。

# Web 账号接入

2026-10-17。当前源码支持 Web 群晖账号登录、按需 OTP、服务器验证后的稳定身份、刷新恢复、退出、取消、账号本机数据隔离，以及 [公开挂载资料访问](web-library.md) 和 [桌游评论](game-comments.md)。游客可以读取已发布资料及公开评论；发布、回复、点赞与删除自己的评论要求登录。2026-10-18 源码已通过同源 `/api/sync/` 接入私人云同步和收藏/投票公共统计，复用原有增量引擎，不另建账号数据库；待构建与 NAS 部署验收。Android/Windows 保留原生直连及原安全存储。

群晖不支持公网回环时，交付 Compose 的 `extra_hosts` 将 `cznas.pp.ua` 固定解析到 **192.168.1.55**，仅影响账号容器。DSM 请求仍使用 `https://cznas.pp.ua:5001`，HTTP Host、TLS SNI 和证书校验保留，实际 TCP 连接到内网 IP；不能直接把 HTTPS URL 改成 IP 并关闭证书校验。浏览器入口与原生端地址不变。当前开发电脑不能连通该内网地址，尚未完成 NAS 内部署后的验证；本轮仅修改源码和部署模板，没有更新已交付 TAR。

## 结构与复用

浏览器 → 同源 `/api/account/` → Nginx → `web-account:8000` → 固定配置的 DSM HTTPS API。网关不开放宿主机端口，没有任意 URL 代理或任意文件写入接口；仅评论写接口允许当前账号按固定快照协议写自己的记录、受控初始化自己的 UID 目录。公开资料校验与内部文件转发见专项文档。前端在 `web_account_gateway.dart` 实现现有 `IdentityGateway`，继续复用 `app_identity` 的 `IdentityController`、已验证身份状态与 `AccountService` 的账号作用域，不修改共享包。

共享 `SynologyIdentityGateway` 明确拒绝 Web，依赖原生安全存储，不能直接用于浏览器；Python 网关也不能导入 Flutter 包。因此仅将它的 API 发现 → Auth v6 → FileStation.Info v2 验证 UID 流程适配到 HTTPX，HTTP/ASGI、Cookie 和路由复用 Starlette，不实现第二套用户数据库。协议依据：[DSM 官方登录流程](https://kb.synology.com/en-global/DG/DSM_Login_Web_API_Guide/2)。

身份 ID 仍为 SHA-256(`synology-direct-v1|<canonical origin>|<DSM UID>`)，账号名只作显示。必须将 `SYNOLOGY_IDENTITY_ORIGIN` 配成原生端既有 canonical origin，才能保持身份相同；浏览器本机数据和原生设备本机数据不会因此自动复制，云同步仍是独立能力。

## 请求与会话

| 接口 | 行为 |
| --- | --- |
| GET `/api/account/config` | 返回受信任登录地址与 canonical origin，不包含凭据 |
| GET `/api/account/session` | 建立匿名 Cookie 或向 DSM 验证现有会话；返回已验证用户或 null |
| POST `/api/account/login` | 只接受 account/password/可选 otp；登录并验证 UID 后才返回用户 |
| POST `/api/account/logout` | 先使站点会话失效、取消在途登录，再尽力撤销 DSM 会话 |

所有请求要求 `X-Board-Game-Request: 1`；存在 Origin 时必须与配置完全一致，拒绝 cross-site，不开放 CORS。浏览器密码仅放 POST 正文，服务端 DSM 请求也使用 POST；会话通过逐请求 `id` Cookie 和 `X-SYNO-TOKEN` 请求头传递，不放入 URL 或 POST 表单。无账号请求显式覆盖共享客户端的 Cookie，账号请求也不使用全局 Cookie jar，防止跨账号串用。不跟随上游重定向，TLS 校验开启。输入最大 8 KiB，上游响应最大 64 KiB；单次上游请求 8 秒、登录总预算 18 秒、验证 12 秒，退出撤销等待最多 2 秒。登录按 IP 和账号分别限制每分钟 10 次，最多保留 4096 个限流键；失败不自动重试。

Cookie 是 256 位随机站点标识，HttpOnly、Secure、SameSite=Strict、Path=/，不包含 NAS SID/SynoToken/密码。SID 与 SynoToken 仅存服务端内存；最多 1024 个会话，空闲 30 分钟、绝对 8 小时过期，单 worker。网关重启后用户需重新登录，不使用数据库或把会话写入镜像。浏览器不保存密码或登录历史；只有退出失败时存一个不含身份和凭据的布尔标记，刷新后先补退出，禁止恢复旧登录。

取消、退出和过期都会递增服务端会话版本；晚到登录只能撤销自己的候选 NAS 会话，不能重新发布身份。多标签共用站点 Cookie，其他标签下一次会话验证会发现退出。客户端初始化、返回前台和前台每 60 秒继续使用现有账号验证调度；定时器不保证后台标签准时执行。登录状态不代表资料访问资格，Web 不生成或保存 WebDAV 密码。

## 部署

2026-10-18 HTTPS 入口诊断：当前网站已通过群晖反代在 `https://cznas.pp.ua:18887` 返回页面。只读接口实测该 Origin 返回 403、旧 HTTP 8887 Origin 返回 200，确认是配置不匹配。交付 YAML 和未来默认值已改为 `WEB_PUBLIC_ORIGIN=https://cznas.pp.ua:18887`、`WEB_ALLOW_INSECURE_HTTP=false`；容器端口仍是 8887:8080，更新配置须重新创建账号网关容器并刷新网页。容器不需要监听 TLS，也不依赖不可信的转发头猜测浏览器 origin。Web AI 的独立跨域问题和同源转发见 [Web AI](web-ai.md)。

群晖部署直接编辑交付目录 `release/reports/docker-linux-amd64/docker-compose.yml` 中的配置，无需 `.env`。以下为对应配置名称；仅开发源码构建时复制 `packaging/docker/.env.example` 为 `.env`：

```dotenv
WEB_PORT=8887
SYNOLOGY_ORIGIN=https://nas.example:5001
SYNOLOGY_IDENTITY_ORIGIN=https://nas.example:5001
WEB_PUBLIC_ORIGIN=https://board-games.example
WEB_ALLOW_INSECURE_HTTP=false
```

`SYNOLOGY_ORIGIN` 是容器可访问、证书有效的 DSM 地址，不能填容器自身 localhost；canonical origin 可与其不同，但应代表同一台 NAS。`WEB_PUBLIC_ORIGIN` 必须是浏览器地址栏中的完整 origin（包含非默认端口），网站入口应由 NAS HTTPS 反向代理转发到 8887。只在明确的本机/内网 HTTP 测试中将 `WEB_ALLOW_INSECURE_HTTP=true`，同时把 public origin 改为实际 HTTP 地址；这种模式会取消 Cookie 的 Secure 属性。自签 CA 可通过只读挂载 CA 文件并设置 `DSM_CA_FILE` 加入信任，不提供关闭证书验证的开关。

默认使用预构建镜像包的 `sh deploy.sh ../../board-game-agent-linux-amd64-images.tar` 导入并启动两个服务，NAS 不执行构建；源码开发须显式追加 `docker-compose.build.yml`。网关有独立的 `Dockerfile.dockerignore`，构建上下文只纳入 app.py、library.py、依赖清单与 Docker 配置，不发送资料库、发布包、凭据或本机缓存。另需设置资料挂载的两个路径，见 [部署说明](docker-deployment.md)。原始 `flutter run` 或纯静态预览没有 `/api/account/` 和 `/library/`，不能当成已部署登录或资料访问。没有修改 NAS 权限、创建目录或写入真实账号测试数据。现有静态 `/healthz` 仍只代表 Nginx 存活，不代表 DSM 可达。

## 依赖与验收

### 2026-10-17 真实 NAS 诊断与源码修复

用户已确认当前域名为 `cznas.pp.ua`。旧 `cznas.dpdns.org` 的 5001/5006 返回新域名证书，旧地址的主机名校验失败；运行连接应使用新域名，不能关闭 TLS 校验。历史账号命名空间与网络入口分别配置，不因更换入口重置已有账号 ID。

新地址 WebDAV PROPFIND 207、目录清单 GET 200（24 款）通过。DSM 登录、原生端式 UID 查询、FileStation `getinfo` 的 `real_path` 查询以及单字节 Range 206 权限读取通过，确认资料真实目录是 `/volume2/friend/apps/board_game_agent/board-game-lib`。测试仅临时登录和读取，完成后注销，没有写入 NAS 文件或改变权限。

同一次 DSM 会话内，仅将 `_sid` 和 `SynoToken` 放在 POST 表单中，FileStation.Info 返回 119；认证放在查询参数中，或逐请求 `id` Cookie 配合 `X-SYNO-TOKEN` 请求头时查询成功。不能因模拟服务器接受 POST 字段就声称已通过真实 DSM 网关登录。

**源码及 2026-10-17 交付镜像已修复**：`Dsm.api()` 的身份查询、会话复查和退出，以及 `readable()` 的权限探测，统一使用逐请求 Cookie + 校验令牌请求头，保持认证信息不进入 URL，不关闭 TLS 校验。Cookie 值限制为 RFC 6265 cookie-octet，令牌限制为无空白/控制字符的 ASCII；无效值在发送前拒绝。共享 HTTP 客户端的响应 Cookie 不能替代当前请求所属账号的会话。

新增 5 项真实协议回归，覆盖 POST 表单会话被拒绝、并发双账号隔离、共享 Cookie 污染、缺失令牌及非法头部值；原账号、资料与 Nginx 模拟服务器也改为要求正确的 Cookie 和请求头。网关自动化测试 40 项通过，1 项本机 Nginx 集成因未配置 `NGINX_BIN` 跳过。Docker 交付验证脚本的模拟 DSM 也执行相同规则，不再放过旧镜像的错误请求。

修复阶段使用既有 Python 运行镜像只读挂载当前源码，直连真实 `cznas.pp.ua` 验证 6 项通过：登录并确认 UID、同一会话身份复查、目录清单权限、真实已登记 PDF 权限、DSM 退出及退出后旧会话被拒绝。随后按用户要求重新构建并覆盖固定 TAR；新镜像在不挂载源码的情况下再次通过相同 6 项真实 NAS 检查，镜像内网关源码摘要与修复源码一致，报告为 `release/reports/docker-linux-amd64/live-nas-validation.json`。新 TAR 的无 `.env` 解析、真实导入与 Nginx/网关运行、严格模拟 DSM 登录、PDF Range/ETag/HEAD 等 18 项检查也通过，见同目录 `validation.json`。验证未记录密码、SID 或 Token，也未改 NAS 文件或权限。

网页预设 `http://cznas.pp.ua:8887` 从开发电脑连接被拒绝，尚不能区分 NAS 容器未监听或外部端口未转发；未操作路由器、反向代理或群晖 Container Manager。真实 Docker 网页登录、容器到 DSM 的连接以及 NAS 窄/宽屏浏览器验收仍未完成。

| 组件 | 版本/许可证 | 使用范围及升级检查 |
| --- | --- | --- |
| Starlette | 1.8.0 / BSD-3-Clause | ASGI 路由、Cookie 和生命周期；检查请求解析与 Cookie 行为变化 |
| HTTPX | 0.28.1 / BSD-3-Clause | 固定 DSM 上游、TLS、连接池及流式响应限制；检查超时、证书与代理策略 |
| Uvicorn | 0.54.0 / BSD-3-Clause | ASGI 运行服务，关闭访问日志及代理头自动信任；维持单 worker |

来源：[Starlette](https://github.com/Kludex/starlette)、[HTTPX](https://github.com/encode/httpx)、[Uvicorn](https://github.com/Kludex/uvicorn)。新依赖只用于独立服务，不进入 Flutter。顶层版本固定在 requirements.txt；升级需重跑登录、退出竞态与输入边界测试。未完成外部漏洞扫描或真实 NAS 上线验收，不声称已通过生产安全审计。

服务端测试运行 `PYTHONPATH=<测试依赖目录> python -m unittest discover -s services/web_account/tests -v`；2026-10-16 资料接入后共 36 项通过（设置 `NGINX_BIN` 包含真实 Nginx 传输测试），使用 HTTPX 假 DSM，不访问实际 NAS。Flutter 全量 677 项通过，覆盖同源请求、OTP、恢复、退出补偿、晚到响应、320/1440 dp 大字体账户页、资料缓存/静默检查及旧原生行为；静态检查通过。此前 Chrome 浏览器测试停留在加载阶段后终止，未计作通过；不能将宿主机 widget 测试视为完整浏览器联调。本轮不构建、上传、启动 NAS 容器或测试真实凭据。真实 DSM（含 OTP）、HTTPS Cookie、NAS 反向代理及容器联调需部署后验收。

回滚使用前一版 Web 与 Compose 配置。网关无持久数据库，停止服务即可使站点会话失效；保留浏览器各账号业务数据，不清理 NAS 文件。同源资料源已作为后台替换接入，不新增前台切换提示；状态与检查界面本轮未调整。

## Web 账号同步适配（2026-10-18）

`WebAccountGateway` 为 `AccountCloudSync` 提供 `WebPrivateSyncFiles` 与 `WebPublicSyncFiles`，同一浏览器 HttpOnly 会话经 Nginx `/api/sync/{private|public}/{entries|file}` 到 DSM FileStation。个人日志在 `/home/Apps/board_game_agent/sync/v1/<environment>/operations`，环境、身份和 dataset ID 沿用原生端的历史 identity origin；收藏/投票公共快照在 `/<ACCOUNT_SHARED_FOLDER>/apps/board_game_agent/public/v1`。共享目录默认 friend，由服务器配置返回给前端，不接收任意客户端 NAS 路径。

不增加私人目录宿主机挂载，不用容器读取身份代替用户访问 home。登录后的初始化同步、收藏/投票立即发布、其他修改 4 秒防抖、60 秒补拉，以及账号页暂停/重试都复用 AccountCloudSync；原生网络传输不变。浏览器已有本地数据和待上传记录参与同一引擎合并，不清空覆盖；取消收藏保留删除版本。

每次请求要求站点会话、同源请求头和绑定的 DSM UID，并校验上游当前身份；账号切换/退出递增会话版本，在每次 DSM 调用前后拒绝旧请求。私人上传仅接受当前账号 dataset、匹配文件名的不可变操作，旧设备目录仅读；公共上传只允许自身 uUID 的收藏/投票快照，读取前后核对 DSM 所有者。上传始终 create_parents=false；只有明确 408 才逐级初始化固定私人目录链或自身公共目录，force_parent=false；共享根由管理员准备。不存在删除、迁移、权限变更或任意 URL 代理。

模拟 DSM 测试覆盖首次初始化、幂等写/冲突、拒绝越权、过期、退出中断、分页及旧日志。Flutter 测试覆盖原生/Web 收藏合并、删除、断网恢复、公共快照及账号切换。模拟通过不等于当前 NAS 已上线；当前交付 TAR 仍是此前 5.0.0+38，未包含本轮改动。

验证记录：55 项 Dart 同步/账号测试通过，相关文件静态检查通过；Linux 网关套件 60 项中 59 项通过、真实 Nginx 测试跳过，该项在 Windows 真实 Nginx 中补验通过（Windows 因 Unix UID 元数据跳过的两项在 Linux 已通过）。源码覆盖现有镜像的 29 项容器检查通过，包括 Nginx → 网关 → HTTPS 模拟 DSM 的私人日志、公共快照、重复上传、冲突拒绝与退出撤销。这里的源码覆盖仅用于开发验证，不代表导出的旧 TAR 已包含新代码。Chrome 测试两次停在套件加载阶段，已终止，未计为通过；未进行真实 NAS 账号数据写入或部署验收。回滚可使用先前匹配的 TAR/YAML，保留浏览器和 NAS 日志，不清理任何账号数据。
