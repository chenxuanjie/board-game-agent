# 桌游导师

Flutter 桌游目录、规则阅读与 AI 助手，支持 Android、Windows 和 Web。游客可浏览公开资料、检查和下载程序更新；账号用于个人收藏、偏好与对话等数据同步。

程序版本以 [pubspec.yaml](pubspec.yaml) 为准，发布批次以 `release-batch.json` 和后台登记为准；README 不另维护版本号或桌游数量。实际可见桌游由后台已发布目录决定。

开发、审查、测试与交付先阅读唯一标准入口：[开发规范与标准](docs/development-standards.md)。源码完成、自动测试通过、镜像发布和现场部署分别验收。

## 当前运行架构

| 内容 | 当前路径 |
| --- | --- |
| 账号 | 共用应用服务；固定 `board_game_agent` 应用作用域，账号/应用/origin 隔离 |
| 公开桌游库 | PostgreSQL 发布目录，经匿名 `/v1/apps/board_game_agent/catalog` 接口读取元数据与资源 |
| 图片、PDF 与正文 | 资源 ID + 发布摘要校验，按需下载；按服务 origin / SHA-256 缓存，读取失败保留已确认缓存 |
| 个人业务 | PowerSync 本机 SQLite、离线上传队列和应用 API；按账号隔离 |
| AI | 登录后默认可选后台 Loomex，同时保留自带 API/Key；游客使用自带配置 |
| Web | 同源 Nginx 转发共用 API / PowerSync；`web-ai` 仅代理自带 Key 的模型请求 |

运行时不再使用旧 `catalog.json`、`game.json`、`manifest.json` 或 DSM/FileStation 账号网关。工程及 NAS 上保留的旧资料是整理源/测试输入，不是运行时回退。WebDAV 实现作为独立备用能力保留，不参与当前默认资料、私人同步或程序升级链路。

Web 默认由 API 传输资源，也可配置 Nginx 只读挂载**新资料存储卷**以加速文件交付；目录和资源权限仍由 SQL/API 决定，不能绕过发布状态直接暴露目录。详见 [SQL 资料客户端](docs/catalog-client.md)、[Web 交付及文件直送](docs/web-ghcr.md)。

## 本地开发

需要当前 `pubspec.yaml` 约束匹配的 Flutter/Dart、Git，以及清单声明的同级 `../shared_packages/` 公共包和仓库内平台插件。直接开发使用实际公共包工作区；镜像 CI 使用已提交的依赖快照。不要把缺失的 path 依赖改成空包。

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

部分现有测试仍通过 `test/support/catalog_fixture.dart` 读取本机 `assets/catalog.json` 与各桌游 JSON 夹具；纯 Git 检出缺少这些整理文件时，全量测试尚不能完全复现。这是待处理的测试输入缺口，不表示客户端需要恢复旧资料协议。具体失败应区分缺夹具与业务回归。

Web 本地预览需要同源 API/模型转发，不能只启动静态文件服务器后验证账号：

```powershell
pwsh -NoProfile -File scripts/start-web-preview.ps1
```

默认 HTTP `http://127.0.0.1:8083`，HTTPS 预留 `8084`；localhost 使用同端口。预览要求已有 Web 编译输出及所需 Python 运行环境；该命令不等于重新构建当前源码。HTTPS 需要显式配置证书。服务地址、浏览器来源白名单和可选文件卷配置见 [Web GHCR 交付](docs/web-ghcr.md)。

Android/Windows 使用应用服务地址。Web 只访问自己的 `/api/`，由预览服务或 Nginx 转发到共用后台；不能将 NAS 反代、浏览器来源配置与普通跨域放行混为一谈。

## 主要功能与行为边界

- 多语言目录、搜索、筛选、详情、规则书和图片浏览；资料公开，文件按需读取。
- 收藏、评论、点赞、排行榜和专题等业务通过应用服务及同步链路更新；个人数据和公共投影分别处理。
- 通用/桌游助手、历史对话、规则知识范围、模型配置、流式回答及资料引用；语音能力依平台支持。
- `仅知识库` 与 `智能补充` 两种回答模式；资料准备使用已校验的发布正文，来源网页只作为追溯信息。
- 会话本机提交与远端上传分开；保存失败阻止更新/账号切换等主动交接，离线但本机已提交时允许升级。
- AI 压缩保存边界和后续输入/输出；停止操作贯穿资料准备与模型请求，清理当前消费者，不中断独立阅读器下载。
- 匿名程序更新清单与下载、资料/程序发布通知；系统通知通道和真机后台行为另行验收。

## 构建与发布

APK、Windows 和 Web 共用程序版本与后台发布批次机制。确定语义版本、申请编号、提交并冻结来源后，再按授权构建/发布；重试与补平台复用原批次，构建不自行递增编号。规则见 [版本与发布标准](docs/development-standards.md#delivery)。

- **APK / Windows**：使用共享 `flutter-release-publisher`；项目 [package-app-release.ps1](scripts/package-app-release.ps1) 包装已构建产物的打包/发布，打包不等于重新编译。匿名更新契约见 [游客程序更新](docs/public-updates.md)。
- **Web 镜像**：受支持入口为 [web-ghcr.yml](.github/workflows/web-ghcr.yml)，构建、验收并发布 Web 与 BYOK 代理两张镜像。工具为 `scripts/ghcr_web_release.py`，上下文准备为 `scripts/docker_build_context.py`。
- **NAS Web Compose**：使用 [docker-compose.ghcr.yml](packaging/docker/docker-compose.ghcr.yml) 或工作流生成的固定摘要版本。HTTP `8083:8080`，群晖反代 HTTPS `8084`；重新应用项目才拉取并重建，单纯重启旧容器不会更新镜像。
- **共用后台 Compose**：属于独立 `app_data_service` 工程，包含 PostgreSQL、API、PowerSync；不是这里的 Web Compose。数据库结构变更按后台迁移流程处理。

旧 `build-docker-release.py/.ps1`、`package-docker.ps1`、`verify-docker-release.py`、`packaging/docker/deploy.sh` 及根 Compose 均已退役，直接报错退出，不再生成账号网关 TAR/源码 ZIP。历史交付与验收资料仍可查阅，但不能作为当前部署命令；已有 NAS 数据和旧产物不会自动删除。

## 代码与专项文档

- 结构与长期规则：[开发规范与标准](docs/development-standards.md)
- 账号、个人业务与公共业务：[业务接入记录](docs/service-business.md)
- 资料版本、文件和离线边界：[SQL 资料客户端](docs/catalog-client.md)
- Loomex 与自带配置：[模型服务](docs/loomex-service.md)
- Web 部署、本机预览及 NAS 文件加速：[Web GHCR 交付](docs/web-ghcr.md)
- Android 下载后台行为：[后台更新](docs/android-background-updates.md)
- 历史旧网关交付：[Docker 历史记录](docs/docker-deployment.md)

应用业务位于 `lib/features/`，共享用例入口位于 `lib/app/state/`，宽窄屏界面位于 `lib/ui/`。后台和公共包是独立仓库；调整本应用不代表它们已同步发布或部署。
