# SQL 资料库客户端接入

2026-10-29。客户端使用 `board_game_agent/catalog` 契约；P2 增加公共发布通知源码，尚未部署新后台或构建新客户端。

## 读取与身份

- Android、Windows 使用应用服务地址下的 `/v1/apps/board_game_agent/catalog`；Web 使用同源 `/api/v1/apps/board_game_agent/catalog`。资料请求匿名发送，复用现有跨平台 HTTP/代理适配，不携带账号密码、认证头或自行构造 Cookie。
- 首次从分页目录发现版次，最多四个并发详情请求。每页、每份详情及结束水位必须处于同一发布版本；中途发布导致版本变化时有限重试，失败保留上次完整数据。
- `GameManifest` 是 SQL 版次的客户端领域模型，直接映射多语言、图片/正文绑定和公开资源权限。运行时不转换或读取旧 `catalog.json`、`game.json`、`manifest.json`，不叠加内置游戏条目，不扫描 WebDAV。
- 资料列表由同一批已验证的版次/资源构建，不再独立读取另一套清单。游戏 ID、slug 沿用服务端稳定身份；登录、私人数据和社区同步保持独立。

## 文件与离线

- 下载使用资源 ID 和发布摘要，拒绝偏离约定的内容地址。图片和文档通过同一资源表解析；网页 PDF 使用同源地址按需分段读取，原生文档流式写临时文件并校验 SHA-256 后替换。
- 新缓存命名空间为 `board-catalog-v1`，按服务 origin 隔离目录快照、按摘要隔离文件版本。只恢复新 API 完整快照，不读旧缓存/内置 JSON；旧真实缓存和 NAS 文件没有自动删除。
- 网络或校验失败保留已确认快照和文件。同摘要文件可离线使用；新版本下载失败时不以旧版本文件冒充新版本。下架资源不再出现在当前资源映射中。
- JSON 请求最多 4 MiB，累计目录元数据预算 16 MiB；单次内存文件读取最多 64 MiB，原生流式文档最多 512 MiB。请求预算 20 秒，目录任务 60 秒，控制器 65 秒，原生文档下载 5 分钟。关闭应用或服务地址切换时取消实际传输并拒绝迟到结果。
- 安装资源声明移除旧桌游目录 JSON、图片、PDF 和正文；原始整理文件仍保留在工程及 NAS，只是客户端不再打包、读取它们。首页预取前六个游戏的封面/背景，其余图片及文档按需缓存。

## 更新与界面

- 启动、回到前台和手动检查读取发布版本。P2 移除一分钟可用性/资料轮询，公共 PowerSync 接收已提交的资料水位；重连时补读权威版本，版本不变时不枚举游戏/文件。
- 版本变化后读取 `/changes` 的全部分页，只获取有变化的版次详情，并应用下架。完整快照持久化、验证后才切换内存版本；刷新失败不会清空现有目录。
- 新元数据自动应用；移除旧的逐文件检查、旧清单覆盖和批量下载后才更新目录的流程。手动入口统一为“检查资料更新”，最近变更展示已应用的桌游，PDF 继续按需下载。
- P2 通过 `publication_versions` 接收事务内更新的版本水位，继续使用 `/changes` 补齐全部分页，不把 PDF/图片正文塞入通知。新水位到达正在进行的检查时安排后续读取；失败保留完整缓存并有限重试，重连/回前台再次补齐。
- 发布通知需要包含 `0017_publication_versions` 的 API 及对应 PowerSync 规则；该迁移接在 P1 的 `0016_release_architecture` 后。只更新客户端或只重启旧后台都不会获得通知。2026-11-01 补齐 Web 本地同源预览和可选 NAS 文件交付源码；Web 继续使用同一 `/catalog` 元数据与资源 ID，实际部署验收见 [Web 交付](web-ghcr.md)。系统通知栏推送属于独立链路。

## 验证记录

`test/public_library_service_test.dart` 覆盖分页/版本、下架、摘要缓存、断网、来源隔离、超时和 Web 内容路径；控制器及资料页回归见 `library_update_flow_test.dart`、`desktop_library_index_test.dart`。UI 测试使用 `test/support/catalog_fixture.dart` 将整理样本转换为新协议；这一转换只在测试中存在。

本轮本机检查：Dart 格式检查通过，`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 全量 558 项通过。未构建 APK、EXE、Web 或 Docker 产物。

显式只读现场探针：

```powershell
flutter test test/probes/catalog_live_probe.dart --dart-define=BOARD_CATALOG_ORIGIN=https://cznas.pp.ua:18281
```

本机已实测 NAS 发布版本 1、24 个桌游、292 个公开资源，抽查图片、1,170,736 字节和 10,466,840 字节 PDF，摘要匹配；记录位于忽略的 `.local/reports/client-catalog-live.json`。这些是新客户端网络/解析/缓存链路的主机测试，不代表 APK/EXE 安装产物或 Web 部署已经验收。
