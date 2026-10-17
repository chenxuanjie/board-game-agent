# 本地交付产物

`release/` 是当前交付目录，不是历史仓库。Android、Windows 各保留最新一套。Docker 每种架构只生成一个固定名称的镜像 TAR，成功后覆盖旧文件；应用版本与内部镜像标签记录在配套元数据中。

| 类型 | 保留文件 |
| --- | --- |
| Android | 最新 APK 与对应 `.release.json` |
| Windows | 最新 Setup.exe、对应 `.release.json`、当前 Windows manifest |
| Docker | `board-game-agent-linux-amd64-images.tar`，同名覆盖，不生成 ZIP |
| 配套资料 | 群晖专用 Compose、版本、摘要和验证记录集中在 `release/reports/docker-linux-amd64/`，同名覆盖；无需 `.env` |

Docker 只交付 TAR 的直接链接，用户在 Container Manager“映像 → 导入”选择该文件。配套小文件独立保存，不再生成内部或外层部署 ZIP。

## Native 打包与发布

编译仍沿用 `flutter-release-publisher` 的固定 build 入口。把既有编译结果制作成本地交付包时，使用本项目包装入口，它准确匹配当前项目的私有发布 profile，并调用原共享发布器：

```powershell
./scripts/package-app-release.ps1 -Target android
./scripts/package-app-release.ps1 -Target windows
```

默认 `Mode=package`，只打包本地已有编译结果，不上传。只有用户明确要求发布/推送时，才使用对应命令：

```powershell
./scripts/package-app-release.ps1 -Target android -Mode release -BumpBuild
./scripts/package-app-release.ps1 -Target windows -Mode release
./scripts/package-app-release.ps1 -Target android -Mode push
```

底层仍使用共享发布器的 package/release/push，不复制编译、签名、OTA 或上传实现。发布配置和凭据仍位于 skill 私有 profile，不进入工程。成功返回后调用 `release_retention.py` 清理同平台旧包；失败时不调用清理。远端发布历史、NAS 数据和 Docker 引擎的镜像/缓存不属于此本地清理范围。

## Docker

`scripts/build-docker-release.ps1` 调用 Skill publisher，项目 Docker profile 已启用 `bumpBuild: true`：每次 build 将 pubspec 构建号递增一次（5.0.0+38 → 5.0.0+39），构建/验证失败恢复，plan/verify 不变；两个镜像、YAML 与报告均使用该版本。底层 `.py` 仅供 publisher 调用，本身不递增版本。在两个镜像构建、导出及 TAR 内容校验完成后，通过同文件系统原子替换覆盖固定交付文件。空导出、损坏 TAR、平台/镜像不符以及构建失败均保留旧 TAR。每次只做一轮镜像构建和一次合并导出，不再制作 ZIP；配套目录中的 `validation.json` 在新构建后失效，不沿用旧成功记录。

实际命令链为脚本调用 `docker buildx build --load --platform linux/amd64` 构建镜像，再用 `docker image save --output images.tar <网页镜像> <账号网关镜像>` 导出。交付 TAR 是 Docker 保存的真实镜像归档，包含两个镜像，不是源码压缩包，也不是把 ZIP 改扩展名。

开发用源码包由 `scripts/package-docker.ps1` 输出到 `build/docker-source/`，只留最新源码 ZIP，不再与交付镜像混放。

## 手动整理

```powershell
python scripts/release_retention.py --dry-run
python scripts/release_retention.py
```

可选 `--platform android|windows|docker`。Native 按版本和配套记录验证大小、SHA-256 与 manifest；Docker 验证固定 TAR 中的两个镜像、平台、层文件和配套摘要，之后清理遗留版本化 TAR/ZIP。没有有效固定 TAR 时不擅自删除旧镜像文件。

只处理明确属于本程序的已知文件名，不递归删除目录，不跟随符号链接或 junction，不删除未知文件，也不默认把旧包移到隐藏历史目录。2026-10-17 首次整理沿用当前实际已有产物，没有重新构建：APK 为 `4.1.0+37`，Windows 安装包为 `4.1.0+35`，Docker 为 `4.1.0+37`。
