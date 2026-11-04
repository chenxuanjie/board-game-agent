# NAS 镜像导入文件

> 历史账号网关交付说明。本文配套的旧构建/导入入口已退役，不能生成当前协议的部署。当前入口见 [Web GHCR 交付](../../docs/web-ghcr.md)；已有历史镜像包和 NAS 数据不作清理。

交付文件为 `board-game-agent-linux-amd64-images.tar`，可直接在 Container Manager“映像 → 导入”选择。它包含已构建的 Web 与账号网关两个镜像，不需要解压 ZIP。桌游正文不在镜像中，继续读取 NAS 既有只读目录。

**DSM 会话兼容修复**：网关采用逐请求 Cookie 和 `X-SYNO-TOKEN`，解决只在 POST 表单中传会话导致的 DSM 119。新域名、资料路径及会话协议已通过真实 NAS 读取验证。本次镜像版本以 `release.json` 为准，镜像部署验证结果见 `validation.json`。NAS 网页可访问不代表资料挂载的容器身份正确，部署后还需验证目录、规则书与评论读取。

图形界面部署：导入后使用本目录的 `docker-compose.yml` 创建项目。无需 `.env`，镜像名称、标签和架构已固定匹配 TAR。资料目录预填 `/volume2/friend/apps/board_game_agent/board-game-lib`，评论目录预填 `/volume2/friend/apps/board_game_agent_comments/public/v1`。DSM 使用 `https://cznas.pp.ua:5001`，账号容器通过 `extra_hosts` 将该域名解析为 `192.168.1.55`，保留证书验证并避免公网回环；浏览器使用 `https://cznas.pp.ua:18887`，群晖 HTTPS 反代转到容器外部端口 8887。只有更换路径或访问地址时才需要修改以下字段：

| YAML 字段 | 填写内容 |
| --- | --- |
| 目标为 `/data/library` 的两处 `source` | 同一个资料库物理路径，必须已存在且内有 `assets/catalog.json` |
| 目标为 `/data/comments` 的 `source` | 已有评论公共目录，只读挂载；不能填私人账号目录 |
| `extra_hosts` | `cznas.pp.ua:192.168.1.55`，使账号容器在 NAS 内网连接 DSM |
| 两处 `user` | 已核验的 NAS 读取身份 `1028:100`；若迁移 NAS，按实际 UID/GID 配置，不修改 NAS 权限 |
| `LIBRARY_NAS_PATH` | 同一目录的 FileStation 路径，去掉 `/volume2` 等卷名前缀 |
| `SYNOLOGY_ORIGIN` | 容器可访问、证书有效的 DSM HTTPS 地址 |
| `SYNOLOGY_IDENTITY_ORIGIN` | 原生端保留的历史账号 ID 命名空间；不是连接目标，旧域名用于维持账号 ID |
| `WEB_PUBLIC_ORIGIN` | 浏览器实际访问网站的地址，不带路径 |
| `WEB_ALLOW_INSECURE_HTTP` | 局域网 HTTP 测试填字符串 `"true"`；HTTPS 网站填 `"false"` |
| `AI_ALLOWED_ORIGINS` | Web AI 转发允许的 HTTPS origin 列表，逗号分隔、不带 `/v1`；不填 Key |

默认外部端口为 **8887**，账号网关端口不对外发布。不在配置中填写账号或密码，每位用户在网页登录。网页必须按 `WEB_PUBLIC_ORIGIN` 的实际地址访问；改用内网 IP 或 HTTPS 反向代理时同步修改该字段和 HTTP 选项。配置填写完成不代表域名到 NAS 的网络转发已验证。

更改上述环境变量后须更新项目并重新创建账号网关容器，仅重启旧容器不会更换环境变量。流式 AI 路由已在容器 Nginx 关闭缓冲；外层反代也应保留流式响应并设置足够读取超时。镜像是否包含 AI 路由以交付版本及验证报告为准。

游客可以读取已发布资料和公开评论；发布、回复、点赞及删除自己的评论要求登录。挂载目录不自动创建、不修改 NAS 权限。评论写入使用当前账号的 DSM 会话，容器挂载仍是只读。

命令行部署：将 TAR 和 `reports/docker-linux-amd64/` 配套目录复制到 NAS，保持相对布局。进入配套目录执行：

```sh
sh deploy.sh ../../board-game-agent-linux-amd64-images.tar
```

脚本校验镜像摘要、架构和配置后导入镜像，以 `--no-build --pull never` 启动；NAS 不下载 Flutter、安装依赖或编译。可编辑的 YAML 不纳入传输校验清单，避免填写 NAS 地址后校验失败。资料目录只读挂载。

默认 Compose 项目名为 `board-game-agent`。已有其他项目名时，用 `COMPOSE_PROJECT_NAME=原项目名 sh deploy.sh ../../board-game-agent-linux-amd64-images.tar` 更新原项目。

更新时替换同名 TAR，在新配套 YAML 中填回自己的 NAS 路径和地址，再更新同名项目。网关重建后 Web 用户需要重新登录。固定文件名只保留本地最新一份，如需回滚应自行另存已部署的 TAR 和配置。

`release.json` 记录应用版本、镜像标签、源码修订、镜像 ID、架构与 TAR 摘要；`checksums.sha256` 检查传输损坏，不是数字签名。本目录不包含真实账号配置。

导入成功仅表示镜像加入 Docker；还需启动项目并验证网站、真实群晖登录与资料读取。HTTPS、DSM 连通性和目录访问由部署环境提供。
