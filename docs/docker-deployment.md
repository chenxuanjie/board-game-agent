# Docker 部署

沿用 usv_ground_station 的多阶段构建、Compose 端口映射和自动重启方式。编译阶段使用 Flutter 3.41.9，运行阶段由 Nginx 提供 Web 静态文件。保持现有 Web 行为，不添加账号登录、NAS 资料挂载或 AI 代理。

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

首次构建需要下载 Ubuntu、Nginx、Flutter SDK 与 Pub 依赖，并在 NAS 上编译 Web；需要可访问这些下载源、足够的磁盘及内存。支持对应基础镜像与 Flutter SDK 的 NAS 架构，未在实际 NAS 验证。Dockerfile 的忽略规则位于 `Dockerfile.dockerignore`，需要支持该功能的现代 Docker/BuildKit。

打开 `http://NAS地址:8088`。端口占用时修改 `.env` 的 `WEB_PORT`，重新执行启动命令。端口映射不自行决定内外网可达性；本方案不修改防火墙或路由器。

```sh
docker compose logs --tail=100
docker compose ps
docker compose down
```

程序更新时替换源码部署包后重新构建。需保留旧包以便回滚；回滚到旧包后重新执行 `docker compose up -d --build`。现有浏览器数据按网站 origin 保存，改地址或端口可能改变其存储作用域。

当前未执行本机或 NAS 的镜像构建、容器启动、页面验证，不能将压缩包生成视为部署成功。

通用 `docker-deployer` skill 安装在本机 Codex skills 目录；压缩包中的 `codex-skills/docker-deployer/` 是可复制安装到其他机器的副本。
