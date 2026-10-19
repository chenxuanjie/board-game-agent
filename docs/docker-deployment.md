# Docker 部署

2026-10-16 起，默认交付预构建的两个 Linux 运行镜像。Flutter 编译、Python 依赖安装在开发电脑或构建环境完成，NAS 只导入并运行。外部端口保持 **8887**，账号协议与只读资料挂载不变，见 [Web 账号](web-account.md) 和 [Web 同源资料](web-library.md)。

## 在开发电脑构建镜像版

2026-10-18 读取身份修复（已构建）：NAS FileStation 只读核验确认资料/评论路径存在，所有者为 UID 1028/GID 100，启用 Synology ACL；先前部署的网关却以 65532:65532 运行。受限临时目录在旧身份下复现 catalog 404/评论 503，匹配 1028:100 后正常。Compose 为 Nginx 与网关都配置 `user: "1028:100"`，使用现有 NAS 读取身份，不修改 NAS ACL/所有者。Nginx 使用非特权 8080、只读根文件系统与可写临时目录，外部仍是 8887。权限错误返回 `libraryUnreadable` 或 `commentsUnreadable`，不再当作 404。

受限目录容器测试增加到 22 项，并验证错误 UID 确实读不到测试文件。先完成源码覆盖模式回归，随后通过 Skill publisher 重新构建 V5 5.0.0+38；新 TAR 无源码挂载的 22 项检查全部通过，报告为 `release/reports/docker-linux-amd64/validation.json`，模式是 `imported release images without source mounts`。TAR SHA-256 为 `b2f74477757193bfd4dc978f85e60d1df1f71bd6500ca0b4e4af2d8255476eac`。新 Nginx 启动配置与 YAML 须随新 TAR 一起部署，不能只换 YAML。未修改 NAS 容器配置、权限或真实文件；旧部署已通过真实账号登录/UID 验证，但目录仍 404，新读取身份在 NAS 上尚待更新后验收。

2026-10-17 源码部署模板增加账号容器的 `extra_hosts: ["cznas.pp.ua:192.168.1.55"]`：DSM 的 HTTPS 域名保留，实际访问 NAS 内网 IP，不依赖公网回环。另将既有 `/volume2/friend/apps/board_game_agent_comments/public/v1` 只读挂到账号容器的 `/data/comments`，供游客读评论；评论写入经当前登录账号的 DSM 会话完成。目录须已存在，不自动创建共享根或改权限。浏览器入口仍为 `http://cznas.pp.ua:8887`。这些模板改动须在下次构建后随匹配镜像重新部署；当前 TAR 尚未更新，开发电脑无法直连该内网地址，未声称已完成 NAS 实测。

需要 Python 3、可用的 Linux Docker 引擎和 Buildx；Windows Docker 须使用 Linux 容器。2026-10-16 已在本机 Ubuntu WSL 安装 Docker Engine 29.9.1、Buildx 0.38.0、Compose 5.6.0，真实构建、镜像包和本地容器验收已完成。Windows 10 LTSC 19044 未安装不兼容的新版 Docker Desktop。

默认目标为 `linux/amd64`。参考工程现有 `usv_server` 的 ELF machine 为 62（x86-64），用户要求使用相同架构；此证据不是远程 NAS 实测。脚本可显式选择 `linux/arm64`，但 ARM 构建和运行尚未验证，构建环境须自行具备对应平台支持。

在工程目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-docker-release.ps1
```

该入口统一调用 flutter-release-publisher，已启用构建号递增与失败回退。`-Mode plan` 仅检查配置，`-Mode verify` 仅验证现有镜像，不改版本。

Linux/WSL/构建环境使用同一 Skill publisher（profile 的 projectDir 须匹配运行环境）：

```sh
python3 /path/to/flutter-release-publisher/scripts/flutter_docker_release.py --project /workspace/app --profile /private/profile.json --mode build
```

脚本检查 Docker/Buildx、Linux 引擎和标签冲突，构建 `board-game-agent:<标签>` 与 `board-game-agent-web-account:<同一标签>`，核验 OS、架构和镜像 ID，再用 `docker image save` 合并导出。Flutter 在构建主机的平台执行，最终 Nginx/Python 镜像使用目标 NAS 平台。

构建脚本先创建白名单临时上下文，只复制 Web 声明资源、运行源码与递归 path 依赖，不直接把整个父目录交给 Docker。本次约 82.6 MiB。包源与现有 `pubspec.lock` 保持一致，`flutter pub get --enforce-lockfile` 禁止静默升级依赖。Windows 没有原生 Docker CLI 时，PowerShell 入口自动调用 Ubuntu WSL；其他发行版可用 `-WslDistribution` 指定。

唯一交付文件为 `release/board-game-agent-linux-amd64-images.tar`。每次成功构建、导出并校验后原子替换同名文件，不生成部署 ZIP，不累积版本或时间戳文件。镜像内部标签记录应用版本、Git 修订、dirty 状态与构建时间；显式使用已存在镜像标签仍拒绝覆盖，默认自动生成新的内部标签，不影响固定 TAR 覆盖。构建失败、空导出或无效 TAR 时保留旧文件。不自动安装 Docker、不连接 NAS、不上传。

配套小文件位于 `release/reports/docker-linux-amd64/`：群晖专用 Compose、部署脚本、`release.json`、`checksums.sha256`、`timings.json` 和实际验证后生成的 `validation.json`。交付 YAML 已固定匹配 TAR 的两个镜像引用和架构，所有 NAS 设置直接写在 YAML 中，不依赖 `.env`。目录不打成另一份压缩包，同名更新；新构建清除旧验证结果。首次下载和缓存命中影响实测时间，见 [本地交付产物](release-artifacts.md)。

镜像版不包含完整 Flutter 工程、共享包源码、Flutter SDK、真实 `.env` 或 NAS 正文资料；界面图片、字体和轻量元数据仍属于运行资源。Python 网关的运行代码与依赖位于其镜像中，不是转换为二进制程序。大小以真实构建结果为准，不承诺比源码版更小。

## NAS 导入运行

在 Container Manager“映像 → 导入”直接选择 TAR，确认两个镜像均已导入。随后使用 `release/reports/docker-linux-amd64/docker-compose.yml` 创建/更新项目，不使用根目录开发模板，不需要 `.env`。直接编辑配套 YAML 中的真实配置：

| 配置 | 用途 |
| --- | --- |
| `ports` 中的 `8887:8080` | 宿主机网站端口仍是 8887，非特权 Nginx 容器内为 8080 |
| 两处挂载 `source` | 同一个已存在的 NAS 物理目录，如 `/volume1/friend/apps/board_game_agent/board-game-lib` |
| `LIBRARY_NAS_PATH` | 同一目录的 FileStation 路径，如 `/friend/apps/board_game_agent/board-game-lib` |
| `SYNOLOGY_ORIGIN` | 容器可访问、证书有效的 DSM HTTPS 地址 |
| `SYNOLOGY_IDENTITY_ORIGIN` | 与原生端相同的 canonical origin，保持账号身份一致 |
| `WEB_PUBLIC_ORIGIN` | 浏览器实际网站 origin；HTTPS 反向代理转到 8887 |
| `WEB_ALLOW_INSECURE_HTTP` | 仅局域网 HTTP 测试填字符串 `"true"`；HTTPS 网站填 `"false"` |

当前交付已预填 FileStation `getinfo` 真实确认的 `/volume2/friend/apps/board_game_agent/board-game-lib`、用户确认并通过证书校验的 DSM 地址 `https://cznas.pp.ua:5001`。2026-10-18 按当前截图与只读请求确认的反代入口修正为 `WEB_PUBLIC_ORIGIN=https://cznas.pp.ua:18887`、HTTP 会话选项 `"false"`；容器映射继续 8887:8080。HTTPS 请求带旧 HTTP origin 时返回 200、带新 HTTPS origin 时返回 403，说明部署仍认旧地址；更换 YAML 环境后须重新创建账号网关容器，不能仅重启。旧域名只保留在 `SYNOLOGY_IDENTITY_ORIGIN` 中作为原生端历史账号 ID 命名空间，不作为请求地址。YAML 不填写用户账号密码。根目录 `docker-compose.yml` 的 `.env` 仅用于后面的开发构建入口。

Web AI 同源转发及允许的提供商通过 `AI_ALLOWED_ORIGINS` 配置；模型 Key 不进入 YAML。新路由需要重新构建 Web、Nginx 和账号网关两个镜像，旧 TAR 不包含本次 AI 修改；仅登录 origin 修正可使用旧镜像更新环境。见 [Web AI](web-ai.md)。

资料根内须有 `assets/catalog.json`。两个服务均只读挂载，缺失目录不会自动创建，不调整 NAS 权限。账号网关 8000 端口不向宿主机发布。证书与 HTTP 测试选项见账号文档。

```sh
cd reports/docker-linux-amd64
sh deploy.sh ../../board-game-agent-linux-amd64-images.tar
```

脚本先校验文件校验和、NAS 架构和 Compose 配置，再导入镜像，以 `--no-build --pull never` 启动。默认 Compose 没有 `build` 字段，并设置 `pull_policy: never`，不会在 NAS 编译或拉取不存在的标签。依据：[Compose pull_policy](https://docs.docker.com/reference/compose-file/services/#pull_policy)、[Docker image save](https://docs.docker.com/reference/cli/docker/image/save/)。需要 Docker Compose v2。

默认 Compose 项目名为 `board-game-agent`；已有自定义项目须保留原名称：

```sh
COMPOSE_PROJECT_NAME=原项目名 sh deploy.sh ../../board-game-agent-linux-amd64-images.tar
```

命令行部署时复制 TAR 与 `reports/docker-linux-amd64/` 配套目录到 NAS，保持相对布局。图形界面和命令行均使用同一份无变量 YAML。镜像标签和架构由交付脚本写入，不需要手工填写。传输摘要只覆盖 TAR 和不可编辑的元数据/脚本，不覆盖需要填写 NAS 地址的 YAML。

## 验收、更新与回滚

启动后验证网站、真实群晖登录、资料/PDF 读取及宽窄布局。`/healthz` 只代表 Nginx 存活，不代表 DSM 或资料可用。查看日志、状态时使用相同项目名：

```sh
docker compose -p board-game-agent logs --tail=100
docker compose -p board-game-agent ps
```

更新时替换同名 TAR，在新配套 YAML 中填回自己的 NAS 路径和地址，以相同项目名导入并启动。本地仅保留最新一份；如需回滚，应自行另存已部署的 TAR 和配置。流程不删除 Docker 引擎内旧镜像、浏览器账号数据或 NAS 资料。网关重建后 Web 用户需要重新登录。更改网站 origin/端口可能改变浏览器存储作用域。

Web 宽屏/窄屏不提供应用更新开关、安装包检查或启动版本检查，程序只支持管理员手动更新 Docker。桌游资料修改不需要重建程序，快速/完整检查及后台内容刷新继续工作。

## 保留的源码构建入口

根目录 `Dockerfile` 保留 Flutter 多阶段构建，账号网关使用独立 Dockerfile。开发电脑显式追加构建覆盖文件：

```sh
cp packaging/docker/.env.example .env
# 编辑真实路径、DSM 地址和网站 origin
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

这条开发命令在执行机器上下载工具、安装依赖和编译，不是 NAS 默认交付流程。仍可生成源码 ZIP：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-docker.ps1
```

源码 ZIP 保留 `board-game-agent-<版本>-docker.zip` 命名，默认放在 `build/docker-source/` 并只留最新一份，须与 `release/` 中的 `*-images.tar` 区分。它包含 Flutter 源码、实际 path 依赖、Web 资源、构建覆盖文件和脚本，不包含桌游 docs/PDF、凭据或本机缓存；打包不编译。解压后 `board-game-agent/` 和 `shared_packages/` 保持同级。构建上下文仍由 `Dockerfile.dockerignore` 白名单限制。

## 与 USV 参考方案的关系及验证边界

USV Compose 含 `build: .`，Dockerfile 编译 C++ 和前端，在 NAS 执行时同样由 NAS 编译。本项目保留其多阶段构建、Compose、配置挂载和自动重启思路，默认交付进一步改为开发端预构建镜像；运行服务为 Nginx 与独立 Python 网关。

2026-10-16：脚本与故障测试 15 项通过；真实镜像包部署测试 16 项通过，包括包内 `deploy.sh` 导入启动、网页与编译后 JS、匿名访问拦截、只读挂载、HTTPS 模拟 DSM 登录与会话恢复、PDF Range 206 / ETag 304 / HEAD、缺失文件与注销。验证脚本使用临时资料和独立 Compose 项目，完成后清理测试容器，不操作 NAS。

```sh
python3 scripts/verify-docker-release.py --archive /path/to/board-game-agent-linux-amd64-images.tar
```

需要 Linux Docker、Python 3 和 OpenSSL。脚本先在无 `.env` 的目录解析实际交付 YAML 并核对 TAR 中两个镜像引用，再替换临时资料路径、随机回环端口和模拟 DSM 地址做运行验证；真实 NAS 配置不会被测试值覆盖。结果在配套目录生成 `validation.json`。验证使用既有镜像缓存，真实 NAS 首次导入可能更慢。实测与交付文件见 [本地 Docker 验证记录](docker-validation-2026-10-16.md)。这只证明本地配置解析和模拟环境运行通过，不能等同真实 NAS、真实 DSM 账号或完整浏览器操作验收。

## 本机 WSL 使用说明

PowerShell 中可执行 `wsl -d Ubuntu -- docker ps`；Docker 引擎只提供 WSL Unix socket，未开放 Docker TCP API。Docker 与 `bga-docker-proxy` 已配置为随 Ubuntu systemd 启动，未验证整机重启。

本机 WSL 的 HTTPS 直连不可用，因此安装了本地构建辅助服务：通过 WSL 标准输入输出调用 Windows Python，复用 Windows 已有的 `127.0.0.1:7890` 代理。WSL 辅助服务仅监听 `127.0.0.1:18080` 与私有 Docker 网桥 `172.17.0.1:18080`，没有新增 Windows 防火墙放行规则。Windows 代理须处于运行状态；该辅助服务不进入运行镜像或 NAS 包，也不是 NAS 部署要求。

服务单元为 `/etc/systemd/system/bga-docker-proxy.service`，Linux 辅助脚本在 `/opt/board-game-agent/docker-proxy/`，Windows 脚本在 `%LOCALAPPDATA%/BoardGameAgent/docker-proxy/`；实现源为 `scripts/local-docker-proxy.py`。Docker systemd 代理配置位于 `/etc/systemd/system/docker.service.d/bga-proxy.conf`，构建容器代理位于 Ubuntu 用户的 `~/.docker/config.json`。代理地址、Windows Python 安装位置或 Docker 网桥变动时须相应调整；切换网络后应先验证下载连接。

Docker 官方 APT 更新源已配置于 `/etc/apt/sources.list.d/docker.sources`，签名密钥位于 `/etc/apt/keyrings/docker.gpg`。`/etc/apt/apt.conf.d/90bga-docker-proxy` 仅让该下载域名经上述本地代理；Ubuntu 其他源的网络设置保持原样。官方源 `apt-get update` 与候选版本查询已通过。

2026-10-17 构建时，Dart 经现有代理访问 `pub.flutter-io.cn` 重复出现连接提前关闭；Windows 和 Docker 容器均已验证该站点可直连。仅在 Ubuntu 用户 `~/.docker/config.json` 的 `proxies.default.noProxy` 追加 `pub.flutter-io.cn,storage.flutter-io.cn`，让这两个既有 Flutter 镜像站直连，其他代理、Docker 拉取和 NAS 配置不变。这个本机构建网络设置不会进入交付运行镜像。
