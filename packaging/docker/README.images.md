# NAS 镜像导入文件

交付文件为 `board-game-agent-linux-amd64-images.tar`，可直接在 Container Manager“映像 → 导入”选择。它包含已构建的 Web 与账号网关两个镜像，不需要解压 ZIP。桌游正文不在镜像中，继续读取 NAS 既有只读目录。

**DSM 会话兼容修复**：网关采用逐请求 Cookie 和 `X-SYNO-TOKEN`，解决只在 POST 表单中传会话导致的 DSM 119。新域名、资料路径及修复源码已通过真实 NAS 读取验证。本次镜像版本以 `release.json` 为准，镜像部署验证结果见 `validation.json`。网站 8887 从开发电脑尚不可达，真实 NAS 网站仍需启动后验收。

图形界面部署：导入后使用本目录的 `docker-compose.yml` 创建项目。无需 `.env`，镜像名称、标签和架构已固定匹配 TAR。当前已预填远端 FileStation 实测确认的 `/volume2/friend/apps/board_game_agent/board-game-lib`、用户确认并通过 TLS 校验的群晖地址 `https://cznas.pp.ua:5001`，网站按直接访问 `http://cznas.pp.ua:8887` 配置。8887 从开发电脑目前连接被拒绝，不能视为可用入口。只有更换路径或访问地址时才需要修改以下字段：

| YAML 字段 | 填写内容 |
| --- | --- |
| 两处 `source` | 同一个资料库物理路径，必须已存在且内有 `assets/catalog.json` |
| `LIBRARY_NAS_PATH` | 同一目录的 FileStation 路径，通常去掉 `/volume1` 前缀 |
| `SYNOLOGY_ORIGIN` | 容器可访问、证书有效的 DSM HTTPS 地址 |
| `SYNOLOGY_IDENTITY_ORIGIN` | 原生端保留的历史账号 ID 命名空间；不是连接目标，旧域名用于维持账号 ID |
| `WEB_PUBLIC_ORIGIN` | 浏览器实际访问网站的地址，不带路径 |
| `WEB_ALLOW_INSECURE_HTTP` | 局域网 HTTP 测试填字符串 `"true"`；HTTPS 网站填 `"false"` |

默认外部端口为 **8887**，账号网关端口不对外发布。不在配置中填写账号或密码，每位用户在网页登录。网页必须按 `WEB_PUBLIC_ORIGIN` 的实际地址访问；改用内网 IP 或 HTTPS 反向代理时同步修改该字段和 HTTP 选项。配置填写完成不代表域名到 NAS 的网络转发已验证。

命令行部署：将 TAR 和 `reports/docker-linux-amd64/` 配套目录复制到 NAS，保持相对布局。进入配套目录执行：

```sh
sh deploy.sh ../../board-game-agent-linux-amd64-images.tar
```

脚本校验镜像摘要、架构和配置后导入镜像，以 `--no-build --pull never` 启动；NAS 不下载 Flutter、安装依赖或编译。可编辑的 YAML 不纳入传输校验清单，避免填写 NAS 地址后校验失败。资料目录只读挂载。

默认 Compose 项目名为 `board-game-agent`。已有其他项目名时，用 `COMPOSE_PROJECT_NAME=原项目名 sh deploy.sh ../../board-game-agent-linux-amd64-images.tar` 更新原项目。

更新时替换同名 TAR，在新配套 YAML 中填回自己的 NAS 路径和地址，再更新同名项目。网关重建后 Web 用户需要重新登录。固定文件名只保留本地最新一份，如需回滚应自行另存已部署的 TAR 和配置。

`release.json` 记录应用版本、镜像标签、源码修订、镜像 ID、架构与 TAR 摘要；`checksums.sha256` 检查传输损坏，不是数字签名。本目录不包含真实账号配置。

导入成功仅表示镜像加入 Docker；还需启动项目并验证网站、真实群晖登录与资料读取。HTTPS、DSM 连通性和目录访问由部署环境提供。
