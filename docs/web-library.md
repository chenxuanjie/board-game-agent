# Web 同源资料读取

2026-10-17。Web 游客即可使用同源 HTTP 读取 NAS 挂载的已发布资料；Android/Windows 继续使用原生账号与 WebDAV。状态与检查界面的按钮、文案、布局均保留，不增加资料源切换提示。账号登录见 [Web 账号](web-account.md)，部署见 [Docker 部署](docker-deployment.md)。

## 路径与数据流

2026-10-18 修复：两个读取挂载的服务使用 NAS 已有 UID/GID（核验为 1028:100），避免默认容器用户无法通过 Synology ACL。Nginx 与 Python 都须能读取同一挂载，不能只修网关后让文件转发继续失败。资料仍是只读挂载；权限拒绝返回 503 `libraryUnreadable`，不伪装成文件不存在。没有改动 NAS 权限/所有者。已重构固定 TAR 与配套 YAML，新镜像在受限目录下通过 22 项容器验证；尚未更新 NAS 部署，见 [Docker 部署](docker-deployment.md)。

NAS 上既有资料目录以只读 bind mount 挂载给 Nginx 和账号网关，容器内固定为 `/data/library`，外部网站端口仍为 **8887**。挂载目录内必须有 `assets/catalog.json`，而不是把 `assets` 本身当作挂载根。

```dotenv
LIBRARY_PATH=/volume2/friend/apps/board_game_agent/board-game-lib
LIBRARY_NAS_PATH=/friend/apps/board_game_agent/board-game-lib
```

前者是 Docker 宿主机物理路径，后者是**同一目录**在 FileStation 中的路径。两者由部署管理员对应配置；不能指向不同资料库。Compose 禁止自动创建不存在的宿主机目录，挂载为只读，不挂载共享目录根或私人账号数据。两个容器的运行用户须已有目录读取权限；程序不修改 NAS 权限、不创建或清理资料目录。

| 入口 | 职责 |
| --- | --- |
| `/` | Flutter Web、界面图片、字体和访客轻量目录 |
| `/api/account/` | 原有群晖账号登录及 HttpOnly 站点会话 |
| `/library/assets/...` | 校验启用游戏与发布登记后，由 Nginx 返回挂载文件，无需登录 |
| `/api/library/files` | 返回已发布清单登记的有限文件列表，最多 1000 项、深度最多 10 |
| `/api/library/versions` | 完整检查时读取登记文件的本机存在状态、mtime 纳秒值与大小，不读取 PDF 正文 |
| `/_library_files/` | Nginx 内部入口，外部直接访问一律 404 |

公开资料请求不调用 DSM，也不要求站点会话；网关只校验发布白名单，PDF、图片等正文由 Nginx 从只读挂载返回，不经 WebDAV 或 Python 转发。DSM 离线、登录失败或退出登录均不影响这些公开文件读取；未登记文件始终不可读取。

目录、每个游戏的 `game.json`、`manifest.json` 保持原格式。只允许启用的游戏、其元数据、展示图片和启用且 `available` 的登记资料；拒绝未登记文件、`docs/others`、路径穿越、编码绕过及符号链接。没有通用 URL 代理、目录写入或资料上传接口。

## 检查、更新与缓存

- 沿用现有调度：初始化成功读取目录后一次完整检查；前台 **60 秒**目录探测与快速检查；点击桌游库、通知或设置快速检查仍复用同一任务。浏览器后台定时器受浏览器限制。
- 快速检查只比较 `catalog.json`。发生变化时，Web 在后台重新读取游戏与资料清单，替换已成功加载的内容，不生成“发现资料更新”确认任务；失败保留当前内容和现有重试状态，下次仍会重试。
- 完整检查通过一个同源接口让服务端检查已登记文件的存在状态和版本信息。它在 NAS 本机执行文件元数据检查，不让浏览器逐个向 WebDAV 探测。此接口即时计算结果，**不新增要上传或维护的清单文件**，也不计算全库 SHA-256。
- 远端 catalog 对游客和登录用户都是 Web 权威目录；下架或删除的游戏不会与内置目录重新合并，已发布正文无需登录。
- 文件 ETag 使用 `mtime_ns + size`，每次返回文件或 304 前均重新检查发布白名单。Nginx 提供 PDF 单段 Range/206、HEAD、Content-Length、Last-Modified，网关处理 If-None-Match/304；关闭 Nginx 秒级 ETag 和 If-Modified-Since 判断，避免同一秒内同大小替换被误判为未变。If-Range 无法匹配时可安全回退完整 200。
- PDF 阅读器直接打开同源 URI 并启用 Range，打开前仅 HEAD 验证，不再先把整个 PDF 转为 data URI。AI 读取完整文件仍受现有用途和权限约束，客户端单次正文上限 64 MiB、请求预算 20 秒。
- 小型 JSON/文本只保留在按账号隔离的内存中，总量最多 8 MiB；图片和 PDF 使用私有、需重新校验的 HTTP 缓存。账号切换立即清空内存并中止请求；图片 URL 包含账号和内容版本，防止解码缓存沿用旧账号或旧图片。不再向旧的公共浏览器 CacheStorage 写入资料，也不恢复其中的历史正文。

版本信息不是内容摘要。如果维护方替换内容时同时保留修改时间和大小，元数据比较无法保证发现；新增资源仍须正确登记，并建议先发布文件、最后发布清单。完整检查不遍历未登记文件，也不能等同于全量正文校验；打开实际文件时仍单独检查发布白名单。

## 打包与验证

`pubspec.yaml` 中所有桌游 docs 排除 Web 和 Android，其他原生平台保留原声明。Docker 构建上下文另行排除 docs/PDF；`prepare-web-assets.py` 在部署副本中移除非 Web 资产声明，避免构建引用未带入的文件。源码 ZIP 也只纳入 Web 所需代码、字体、图片及轻量元数据，遇到正文或宽泛游戏目录声明会失败。NAS 资料不复制进源码包或最终镜像。

服务端验收命令：

```sh
python -m unittest discover -s services/web_account/tests -v
```

安装 `requirements.txt` 的依赖后运行；设置 `NGINX_BIN` 可追加真实 Nginx 传输测试。测试使用临时资料和模拟 DSM，覆盖游客 206/304/HEAD、同秒同大小替换、内部路径保护，以及退出后公开文件仍可读取。Windows 测试禁用 Nginx 不支持的 `disable_symlinks` 指令；Linux Docker 配置保留此指令，Python 符号链接拒绝用例单独验证。

Flutter 回归覆盖同源传输、账号切换/晚到响应、请求合并、缓存和超时、目录权威性、静默更新、失败恢复及旧原生检查流程。本轮没有构建产品或 Docker 镜像、生成部署 ZIP、连接真实 NAS 或执行完整浏览器部署验收；测试通过不能等同于实际 NAS 上线验证。回滚使用前一版源码及 Compose 后重建，原只读资料目录不受影响。
