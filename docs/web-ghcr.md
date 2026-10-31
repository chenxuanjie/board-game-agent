# Web GHCR 交付

当前 Web 默认通过 `.github/workflows/web-ghcr.yml` 构建、验证并推送两张 linux/amd64 镜像：
`ghcr.io/chenxuanjie/board-game-agent` 和 `ghcr.io/chenxuanjie/board-game-agent-web-ai`。
前者提供 Flutter、PowerSync Worker/WASM 与新 API 同源转发；后者只提供自带 Key 的受控模型转发，不包含旧登录、FileStation、评论文件或资料扫描接口。

## 端口与服务地址

- 本地及 NAS HTTP 端口为 **8083**，HTTPS 端口为 **8084**。
- NAS Compose 映射 `8083:8080`；群晖反代设置为 HTTPS `cznas.pp.ua:8084` → HTTP `127.0.0.1:8083`。
- 浏览器正式入口为 `https://cznas.pp.ua:8084`。HTTP NAS 地址可验证静态页面，安全 Cookie 登录和完整 Web 数据库使用 HTTPS。
- `APP_SERVICE_UPSTREAM` 默认是 NAS 已有应用服务 `http://192.168.1.55:18280`，可在 Compose 调整为实际内部入口。不把数据库账号、模型 Key 或 DSM 凭据配置进 Web。
- 新入口必须与 API 配置 `APP_DATA_APPLICATIONS.board_game_agent.browser_origin` 一致；保留其他应用配置、签名、密码、数据卷和 API 镜像，只更新此字段后重新应用 API 配置。浏览器 origin 配置不需要数据库迁移或重建 PostgreSQL/PowerSync 镜像。
- 公共同步和个人同步均通过 `/api/powersync/`；账号、资料及社区通过 `/api/v1/apps/board_game_agent/`。Nginx 去除 `/api` 前缀后转发；Cookie、CSRF、Range、SSE 和 WebSocket 头按原契约传递。

每应用在本地登记一对相邻端口，HTTP 使用奇数端口，HTTPS 使用下一个偶数端口。新增分配和冲突迁移按两位递增，先检查其他应用的 HTTP/HTTPS 登记及实际监听；不抢占未知进程。HTTPS 端口预留不等于已安装受信任的开发证书。

## 来源与发布

正式交付前提交版本及相关源码，公共库必须已提交且干净。公共库目前没有远端，运行：

```powershell
python scripts/ghcr_web_release.py snapshot
```

该工具只从实际依赖闭包的已跟踪 `lib`、`assets`、pubspec 和许可生成确定性的源码快照，记录完整提交、版本和每个文件摘要。快照与锁定文件一起提交；修改公共库后须重新生成，不能只改锁文件的提交号。

Actions 使用当前提交与固定依赖快照生成白名单构建上下文，不复制工作区其他应用或私有 profile。先构建实际镜像，再在隔离容器中核对静态资源、跨源隔离响应头、WASM MIME、同源路径、Cookie/CSRF、PDF Range/HEAD、SSE/WebSocket 和模型代理边界；通过后推送 GHCR，并生成固定镜像 digest 的 Compose 与发布记录。未请求完整业务测试时不自动运行 Flutter/后台全套测试，不把模拟接口验证描述为 NAS 登录验收。

镜像同时提供固定版本/提交标签和分支标签。部署优先使用工作流 `web-ghcr-deployment` 附件中的 digest Compose；分支标签适合显式追踪开发分支。配置不包含 `build`，NAS 只拉取镜像并重建容器，不在 NAS 编译 Flutter。

GHCR 包需要目标 NAS 有读取权限。首次发布后核对包可见性；若保持私有，先在 NAS 配置有读取权限的 GHCR 登录。更新原 Web 项目并保留自己的项目名，不删除旧资料或数据库卷。旧 Python 账号容器不属于新 Compose，确认新链路后才按用户授权清理遗留容器。

本机默认预览使用 `http://127.0.0.1:8083`；`8084` 留给本机 HTTPS。NAS 反代和证书由部署者配置，源码或 CI 成功不代表 NAS 已部署。
