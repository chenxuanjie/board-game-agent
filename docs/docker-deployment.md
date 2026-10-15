# Docker 部署

沿用 usv_ground_station 的多阶段构建、Compose 端口映射和自动重启方式。编译阶段使用 Flutter 3.41.9，运行阶段由 Nginx 提供 Web 静态文件。2026-10-16 新增同源 Web 账号网关；资料目录挂载、同源资料读取和 AI 代理尚未接入。登录范围、配置、依赖及验收见 [Web 账号接入](web-account.md)。

## 与参考工程的区别

2026-10-15 核对本机 `apps/usv_ground_station/` 的 `Dockerfile`、`docker-compose.yml`、`config_default.ini` 和 `usv_server.cpp`：

| 项目 | USV Ground Station | 本项目 |
| --- | --- | --- |
| 构建阶段 | Ubuntu 编译 C++；独立 Node 20 阶段用 Babel 编译前端 | Ubuntu 中使用 Flutter 3.41.9 编译 Web |
| 运行阶段 | Ubuntu，启动 `./usv_server` | Nginx 1.28 Alpine，启动 `nginx -g 'daemon off;'` |
| 容器职责 | C++ 同时托管网页、接受 WebSocket、作为 TCP 客户端连接无人艇 | Nginx 提供 Web 文件；独立 Python 账号网关处理 DSM 登录，Flutter Web 界面逻辑仍在浏览器执行 |
| 默认端口 | `8888:8888`，服务监听由 `config.ini` 的 `local_web_port` 决定 | `8887:80`，`.env` 的 `WEB_PORT` 决定外部端口，Nginx 固定监听 80 |
| 配置与存储 | 挂载 `config.ini`，服务可读写配置 | 没有配置文件或 NAS 资料卷挂载；现有浏览器数据仍按网站 origin 保存 |
| 构建输入 | 当前工程目录，排除构建与 Node 缓存 | 父目录作为上下文，白名单纳入本项目与实际引用的本地共享包 |
| 运维 | Compose，`restart: unless-stopped` | 相同重启策略，另有日志轮转和 `/healthz` HTTP 存活检查 |

共同点是编译环境与运行环境分离，最终镜像不携带编译工具，修改源码后重新构建镜像。这里的源码 ZIP 需要解压后构建，不是可通过 `docker load` 导入的镜像归档。`/healthz` 只表示 Nginx 能响应，不代表账号、NAS 或 AI 服务都已验证可用。上述为配置与源码对比，不代表已实测镜像大小、启动速度或 NAS 运行效果。

## 生成部署压缩包

在工程目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-docker.ps1
```

生成 `release/board-game-agent-<版本>-docker.zip`。这是源码构建包，不是已编译镜像；打包本身不需要 Docker 或 Flutter，也不会执行构建或测试。包含当前工作目录中的代码、pubspec 声明的资源、递归引用的本地共享包及 Docker 部署文件。保留 Web 现有资源，不包含本机缓存、发布凭据和旧服务目录。

## 在 NAS 上部署

解压后保留 `board-game-agent/` 与 `shared_packages/` 为同级目录。在群晖 Container Manager 中创建项目，选择解压后的 `board-game-agent` 目录及其 `docker-compose.yml`；或通过 NAS 终端执行：

```sh
cd board-game-agent
cp packaging/docker/.env.example .env
docker compose up -d --build
```

启动前需编辑 `.env` 中的 `SYNOLOGY_ORIGIN`、`SYNOLOGY_IDENTITY_ORIGIN` 和 `WEB_PUBLIC_ORIGIN`。账号 Cookie 默认要求 HTTPS，建议由 NAS 反向代理将网站 HTTPS 入口转到 8887；HTTP 本机/内网测试需显式开启示例中的测试选项。账号网关只在 Compose 内网监听 8000，不向宿主机发布。详见 [Web 账号部署](web-account.md)。

首次构建需要下载 Ubuntu、Nginx、Flutter SDK 与 Pub 依赖，并在 NAS 上编译 Web；需要可访问这些下载源、足够的磁盘及内存。支持对应基础镜像与 Flutter SDK 的 NAS 架构，未在实际 NAS 验证。Dockerfile 的忽略规则位于 `Dockerfile.dockerignore`，需要支持该功能的现代 Docker/BuildKit。

打开 `http://NAS地址:8887`。默认端口映射为宿主机 `8887` → 容器内 Nginx `80`。端口占用时修改 `.env` 的 `WEB_PORT`，重新执行启动命令。已有部署若在 `.env` 中设置了 `WEB_PORT=8088`，需要改为 `WEB_PORT=8887`，再执行 `docker compose up -d` 重建容器以应用映射；仅更改端口不需要重新编译镜像。端口映射不自行决定内外网可达性；本方案不修改防火墙或路由器。

```sh
docker compose logs --tail=100
docker compose ps
docker compose down
```

程序更新时替换源码部署包后重新构建。需保留旧包以便回滚；回滚到旧包后重新执行 `docker compose up -d --build`。现有浏览器数据按网站 origin 保存，改地址或端口可能改变其存储作用域。

当前未执行本机或 NAS 的镜像构建、容器启动、页面验证，不能将压缩包生成视为部署成功。

通用 `docker-deployer` skill 安装在本机 Codex skills 目录；压缩包中的 `codex-skills/docker-deployer/` 是可复制安装到其他机器的副本。
