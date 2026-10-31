# Web GHCR 交付

当前 Web 默认通过 `.github/workflows/web-ghcr.yml` 构建、验证并组织两张 linux/amd64 镜像的发布：
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

Web 镜像提供固定版本/提交标签和分支标签。模型代理以 Linux amd64、固定基础镜像、带摘要的依赖锁及代理源码计算 `inputs-<sha256>` 标签；输入未变时拉取并验证已发布镜像，保留其原始源码提交，不随网页提交重新编译代理。只有仓库明确返回 404 才构建新代理，鉴权或网络错误直接报告。发布记录分别保存 Web 和代理的来源，部署始终固定实际镜像 digest；分支别名仅用于显式追踪。

`main`/`develop` 推送、面向这两个分支的 PR 和手动触发执行镜像工作流；普通功能分支推送不自动构建。纯文档和纯测试的分支变更不触发工作流，手动触发仍执行构建/复用判断。代理及 Web 通过实际镜像检查后才发布。

日常 NAS 部署使用长期不变的 [docker-compose.ghcr.yml](../packaging/docker/docker-compose.ghcr.yml)：两张镜像都引用 `:nas`，设置 `pull_policy: always`。后续发布无需修改 YAML；在群晖重新应用项目，拉取镜像并重新创建容器。只停止/启动既有容器不会检查新镜像，也不意味着后台自动升级。端口、API 地址和其他部署配置变化时仍需调整 Compose。

发布 NAS 通道时，将完成本地构建验证的提交标记为附注候选标签 `web-nas-v<版本>-rc.<序号>+<构建号>`，然后明确推送该标签；也可手动触发工作流并启用 `publish_nas`。只有这两种显式发布入口在验证成功后更新两张镜像的 `nas` 标签，普通分支、PR 和默认手动构建不覆盖 NAS 通道。NAS 发布运行共享同一并发组，防止两个版本同时发布。标签、源码推送和镜像发布仍须按用户授权执行。

工作流 `web-ghcr-deployment` 附件同时保留本次实际 digest 的 Compose 与发布记录，用于定位和回退；发布 NAS 通道时还包含固定标签 Compose。配置不包含 `build`，NAS 只拉取镜像并重建容器，不在 NAS 编译 Flutter。固定标签是可移动的部署入口，实际版本以发布记录中的不可变摘要为准。

## 构建缓存与更新流量

构建上下文生成独立的 `dependency-manifests`，包含实际 path 依赖闭包的包声明及锁文件，先执行 `flutter pub get --enforce-lockfile` 再复制完整源码。只在依赖缓存副本中将根应用版本规范为 `0.0.0`；最终编译恢复真实 pubspec，镜像检查必须核对 `/version.json` 的真实版本和构建号。应用构建号递增不应导致重新下载所有 Dart 依赖。

编译输出由 `scripts/prepare-web-layers.py` 分成引擎、PowerSync、PDF、字体、图片和业务代码六组，保留完整路径及文件字节。生成清单进入业务代码组；每组的时间戳和权限统一，再用 `COPY --link` 形成独立镜像层。不能直接把整个 `build/web` 再复制一遍，重复写入会抵消分层收益。运行镜像不包含 SDK、分组清单或编译缓存。当前 Nginx/Python 基础镜像固定 digest；更新依赖时显式调整并重新验证。

Nginx 使用构建时生成的 SHA-256 ETag 映射，支持强/弱 ETag、列表及通配符重验证；映射独立存放在站点目录之外。静态资源不使用统一时间戳推导的旧 ETag 或 If-Modified-Since 判断，避免同大小内容更新仍命中旧缓存。API 的 ETag、Range、SSE 和 WebSocket 转发保持原契约。构建步骤只复制 Flutter 编译所需输入，运行配置或资源分层脚本变化不应单独触发 Flutter 重编译。

镜像分层减少后续更新所需的压缩层下载量，不代表首次下载大小同比缩小。首次从旧的单一网页层切换，需要获取新的资源层；此后通常只需下载变化的组。删除本地缓存、更新图片/字体/引擎或更换架构时，下载量相应增加，不能承诺每个版本固定下载量。

使用相同架构和压缩设置导出两次真实构建的 OCI 归档，再运行：

```powershell
python scripts/compare-image-layers.py previous.oci.tar updated.oci.tar --output comparison.json
```

工具比较实际层 digest，按新清单中缺失层的压缩字节数计算下载量，支持将已保存的单平台 Registry manifest JSON 作为基线。不用解压后目录大小或未压缩的 Docker save 大小代替网络层大小；结果不包含清单、TLS 及网络重试开销。镜像校验覆盖引擎、字体、PDF、同步资源、真实版本及原有同源接口。

GHCR 包需要目标 NAS 有读取权限。首次发布后核对包可见性；若保持私有，先在 NAS 配置有读取权限的 GHCR 登录。更新原 Web 项目并保留自己的项目名，不删除旧资料或数据库卷。旧 Python 账号容器不属于新 Compose，确认新链路后才按用户授权清理遗留容器。

本机默认预览使用 `http://127.0.0.1:8083`；`8084` 留给本机 HTTPS。NAS 反代和证书由部署者配置，源码或 CI 成功不代表 NAS 已部署。
